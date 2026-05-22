import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:highlight/languages/json.dart' as lang_json;
import 'package:highlight/languages/pgsql.dart' as lang_pgsql;

import '../../theme/app_theme.dart';
import '../../theme/code_theme.dart';

/// A single suggestion shown by the autocomplete popup. [kind] and
/// [matchBoost] are consumed by the ranker in `sql_complete.dart`; the
/// editor itself only reads label/insert/detail/icon/[chainNext].
class CodeSuggestion {
  const CodeSuggestion({
    required this.label,
    required this.insertText,
    this.detail,
    this.icon,
    this.kind = SuggestionKind.keyword,
    this.matchBoost = 0,
    this.chainNext = false,
  });

  final String label;
  final String insertText;
  final String? detail;
  final IconData? icon;
  final SuggestionKind kind;
  final int matchBoost;

  /// When true, accepting this suggestion appends a trailing space and
  /// immediately re-opens the popup for the next token — used for SQL
  /// keywords, table names, and `*` so picking `SELECT → * → FROM →
  /// users → …` flows without ever pressing Ctrl-Space.
  final bool chainNext;
}

enum SuggestionKind { column, alias, table, keyword, snippet }

/// Snapshot of the editor at the moment a suggestion is requested.
/// [manualTrigger] is set by `Ctrl-Space` / `⌃Space` — providers may use
/// it to widen results when the user explicitly asks "what's available?"
class SuggestRequest {
  const SuggestRequest({
    required this.text,
    required this.cursor,
    required this.token,
    required this.tokenStart,
    this.manualTrigger = false,
  });

  final String text;
  final int cursor;
  final String token;
  final int tokenStart;
  final bool manualTrigger;
}

typedef CodeSuggestProvider =
    FutureOr<List<CodeSuggestion>> Function(SuggestRequest);

/// Gutter icon attached to a specific 0-based line index.
class LineIcon {
  const LineIcon({required this.icon, this.onTap, this.tooltip});

  final Widget icon;
  final VoidCallback? onTap;
  final String? tooltip;
}

typedef LineIconBuilder = LineIcon? Function(int line);

/// Soft accent band stretched across lines [startLine]..[endLine] (inclusive,
/// 0-based) — used by the SQL editor to highlight the active statement.
class LineBand {
  const LineBand({
    required this.startLine,
    required this.endLine,
    required this.color,
  });

  final int startLine;
  final int endLine;
  final Color color;
}

/// `TextEditingController` that returns a highlight-tinted `TextSpan` tree
/// using a registered language grammar from the `highlight` package and the
/// shared [apertureCodeStyles] theme map.
class CodeEditorController extends TextEditingController {
  CodeEditorController({super.text, this.language = 'pgsql'}) {
    _registerLanguage(language);
  }

  /// Highlight language name (`pgsql`, `json`, …). Override and call
  /// [notifyListeners] to repaint with a new grammar.
  String language;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    if (text.isEmpty) return TextSpan(text: '', style: base);
    final parsed = highlight.parse(text, language: language);
    return TextSpan(
      style: base,
      children: highlightNodesToSpans(parsed.nodes, base, apertureCodeStyles),
    );
  }
}

final _registeredLanguages = <String>{};

void _registerLanguage(String name) {
  if (!_registeredLanguages.add(name)) return;
  switch (name) {
    case 'pgsql':
      highlight.registerLanguage('pgsql', lang_pgsql.pgsql);
    case 'json':
      highlight.registerLanguage('json', lang_json.json);
  }
}

/// A small, self-contained code editor. Owns the gutter, line numbers, line
/// icons, the highlighted TextField, and an inline autocomplete popup.
///
/// One widget powers the multi-line SQL editor, the single-line clause-bar
/// inputs, and the JSON cell editor — all three share metrics so the same
/// font, padding, and caret rules apply everywhere.
class CodeEditor extends StatefulWidget {
  const CodeEditor({
    super.key,
    required this.controller,
    this.focusNode,
    this.scrollController,
    this.showLineNumbers = false,
    this.singleLine = false,
    this.expands = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.fontSize = 13,
    this.lineHeight = 1.45,
    this.cursorHeight,
    this.background,
    this.hintText,
    this.hintStyle,
    this.lineIcon,
    this.lineBands = const [],
    this.suggest,
    this.gutterWidth = 56,
    this.iconColumnWidth = 18,
    this.onSubmit,
    this.onChanged,
    this.inputFormatters,
    this.textColor,
  });

  /// Any [TextEditingController]; pass a [CodeEditorController] when you
  /// want highlight tinting via the `highlight` package grammar.
  final TextEditingController controller;
  final FocusNode? focusNode;
  final ScrollController? scrollController;

  final bool showLineNumbers;

  /// Single-line mode disables expanding height, multi-line editing, and the
  /// scroll controller hook. Bare Enter falls through to [onSubmit].
  final bool singleLine;

  /// Multi-line only — when true the TextField expands to fill its parent.
  final bool expands;

  final EdgeInsets padding;
  final double fontSize;
  final double lineHeight;
  final double? cursorHeight;
  final Color? background;
  final String? hintText;
  final TextStyle? hintStyle;
  final LineIconBuilder? lineIcon;
  final List<LineBand> lineBands;
  final CodeSuggestProvider? suggest;
  final double gutterWidth;
  final double iconColumnWidth;
  final VoidCallback? onSubmit;
  final ValueChanged<String>? onChanged;
  final List<TextInputFormatter>? inputFormatters;
  final Color? textColor;

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  late FocusNode _focus;
  bool _ownsFocus = false;
  late ScrollController _scroll;
  bool _ownsScroll = false;
  final LayerLink _link = LayerLink();

  double _scrollOffset = 0;

  // Soft-wrap metrics — measured in *painter pixels* so we never round
  // through (fontSize * lineHeight). `_lineTopsPx[i]` is the painter-y of
  // logical line i's first visual row, `_lineHeightsPx[i]` is the pixel
  // height of that whole logical line (one or more visual rows). Cached on
  // (text, bodyWidth); reused by gutter, icons, band, and the popup anchor.
  String? _metricsText;
  double _metricsWidth = -1;
  List<double> _lineTopsPx = const [0];
  List<double> _lineHeightsPx = const [0];
  double _rowHeightPx = 0;

  // Autocomplete. The popup obeys three rules that the old version got
  // wrong: (1) it only re-queries on actual text edits, not when the
  // caret moves with the keyboard; (2) it stays suppressed for one tick
  // after accepting a suggestion, so the controller-change fired by the
  // `controller.value = …` write doesn't immediately re-open with the
  // freshly inserted word as the new prefix; (3) it never opens on its
  // own with an empty token — empty-token popups only happen via the
  // manual `Ctrl-Space` trigger.
  final ValueNotifier<_PopupState> _popup = ValueNotifier(
    const _PopupState.hidden(),
  );
  OverlayEntry? _overlay;
  int _suggestSeq = 0;
  Timer? _suggestDebounce;
  String? _lastSeenText;
  bool _suppressNextAutoTrigger = false;

  TextStyle get _bodyStyle => GoogleFonts.jetBrainsMono(
    fontSize: widget.fontSize,
    height: widget.lineHeight,
    color: widget.textColor ?? AppColors.textPrimary,
  );

  double get _lineBox => widget.fontSize * widget.lineHeight;

  bool get _hasGutter =>
      !widget.singleLine && (widget.showLineNumbers || widget.lineIcon != null);

  double get _effectiveGutterWidth => _hasGutter ? widget.gutterWidth : 0;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? FocusNode();
    _ownsFocus = widget.focusNode == null;
    _focus.onKeyEvent = _onFocusKey;
    _scroll = widget.scrollController ?? ScrollController();
    _ownsScroll = widget.scrollController == null;
    _scroll.addListener(_onScroll);
    widget.controller.addListener(_onControllerChange);
    _focus.addListener(_onFocusChange);
    _lastSeenText = widget.controller.text;
  }

  @override
  void didUpdateWidget(covariant CodeEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onControllerChange);
      widget.controller.addListener(_onControllerChange);
    }
    if (old.focusNode != widget.focusNode) {
      _focus.removeListener(_onFocusChange);
      _focus.onKeyEvent = null;
      if (_ownsFocus) _focus.dispose();
      _focus = widget.focusNode ?? FocusNode();
      _ownsFocus = widget.focusNode == null;
      _focus.onKeyEvent = _onFocusKey;
      _focus.addListener(_onFocusChange);
    }
    if (old.scrollController != widget.scrollController) {
      _scroll.removeListener(_onScroll);
      if (_ownsScroll) _scroll.dispose();
      _scroll = widget.scrollController ?? ScrollController();
      _ownsScroll = widget.scrollController == null;
      _scroll.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _dismissPopup();
    _suggestDebounce?.cancel();
    widget.controller.removeListener(_onControllerChange);
    _focus.removeListener(_onFocusChange);
    _focus.onKeyEvent = null;
    if (_ownsFocus) _focus.dispose();
    _scroll.removeListener(_onScroll);
    if (_ownsScroll) _scroll.dispose();
    _popup.dispose();
    super.dispose();
  }

  KeyEventResult _onFocusKey(FocusNode node, KeyEvent ev) {
    if (ev is! KeyDownEvent && ev is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = ev.logicalKey;
    final hk = HardwareKeyboard.instance;
    final noModifier =
        !hk.isShiftPressed &&
        !hk.isMetaPressed &&
        !hk.isAltPressed &&
        !hk.isControlPressed;
    final isEnter =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    final isTab = key == LogicalKeyboardKey.tab;

    if (_popupOpen) {
      if (key == LogicalKeyboardKey.arrowDown) {
        _movePopup(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        _movePopup(-1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _dismissPopup(suppressNext: true);
        return KeyEventResult.handled;
      }
      // Tab accepts the highlighted suggestion. Enter no longer accepts —
      // it dismisses the popup and falls through to the newline / submit
      // handlers so pressing Return always inserts a line.
      if (noModifier && isTab) {
        final s = _popup.value;
        _acceptSuggestion(s.items[s.selected]);
        return KeyEventResult.handled;
      }
      if (noModifier && isEnter) {
        _dismissPopup();
      }
    }

    // Manual trigger: Ctrl-Space (and ⌃Space on macOS) opens the popup
    // with the full ranked list for the current context, even if the
    // user hasn't typed an identifier prefix yet.
    if (key == LogicalKeyboardKey.space &&
        hk.isControlPressed &&
        !hk.isMetaPressed &&
        !hk.isAltPressed) {
      _requestSuggestions(manualTrigger: true);
      return KeyEventResult.handled;
    }

    // Tab indents a soft tab / the selected lines; Shift-Tab dedents.
    // Single-line inputs keep Tab for focus traversal. The popup-accept
    // case above already returned, so reaching here means no popup.
    if (!widget.singleLine &&
        isTab &&
        !hk.isMetaPressed &&
        !hk.isAltPressed &&
        !hk.isControlPressed) {
      _handleTab(dedent: hk.isShiftPressed);
      return KeyEventResult.handled;
    }

    if (widget.singleLine &&
        widget.onSubmit != null &&
        noModifier &&
        isEnter) {
      widget.onSubmit!();
      return KeyEventResult.handled;
    }

    // Multi-line Enter inserts a newline that copies the current line's
    // leading whitespace, so indentation carries down as you type.
    if (!widget.singleLine && noModifier && isEnter) {
      _handleNewline();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _onScroll() {
    final next = _scroll.hasClients ? _scroll.offset : 0.0;
    if ((next - _scrollOffset).abs() > 0.5) {
      setState(() => _scrollOffset = next);
      _refreshPopupAnchor();
    }
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _dismissPopup();
  }

  void _onControllerChange() {
    widget.onChanged?.call(widget.controller.text);
    final text = widget.controller.text;
    final textChanged = text != _lastSeenText;
    _lastSeenText = text;

    if (widget.suggest != null) {
      if (_suppressNextAutoTrigger) {
        // The accept-suggestion path wrote the controller value, which
        // re-entered this listener. Swallow exactly one trigger so we
        // don't immediately re-open the popup on the inserted word.
        _suppressNextAutoTrigger = false;
      } else if (textChanged) {
        _scheduleSuggest();
      } else if (_popupOpen) {
        // Selection-only change while the popup is up — if the caret has
        // walked off the active token, hide; otherwise leave it alone.
        _reconcilePopupToCaret();
      }
    }

    if (mounted) setState(() {});
  }

  // --- Autocomplete -------------------------------------------------------

  /// Tight debounce — enough to coalesce a flurry of edits inside a
  /// single frame, short enough that the popup feels live as you type.
  static const Duration _suggestDelay = Duration(milliseconds: 60);

  void _scheduleSuggest() {
    _suggestDebounce?.cancel();
    _suggestDebounce = Timer(_suggestDelay, _requestSuggestions);
  }

  Future<void> _requestSuggestions({bool manualTrigger = false}) async {
    if (!mounted || !_focus.hasFocus) return;
    final provider = widget.suggest;
    if (provider == null) return;

    final text = widget.controller.text;
    final cursor = widget.controller.selection.baseOffset;
    if (cursor < 0 || widget.controller.selection.extentOffset != cursor) {
      _dismissPopup();
      return;
    }

    final tokenStart = _tokenStart(text, cursor);
    final token = text.substring(tokenStart, cursor);

    // Empty tokens are handed to the provider too — the SQL engine
    // decides whether the cursor sits in a "natural" completion slot
    // (right after `JOIN `, `,`, `(`, …) and returns a non-empty pool
    // there, or returns [] elsewhere so the popup stays hidden.
    final seq = ++_suggestSeq;
    final res = await provider(
      SuggestRequest(
        text: text,
        cursor: cursor,
        token: token,
        tokenStart: tokenStart,
        manualTrigger: manualTrigger,
      ),
    );
    if (!mounted || seq != _suggestSeq) return;

    if (res.isEmpty) {
      _dismissPopup();
      return;
    }

    _showPopup(res, tokenStart, cursor);
  }

  /// Called on selection-only controller updates while the popup is up.
  /// If the caret has moved outside the active token's word run we hide;
  /// otherwise the popup keeps its existing items (the next text edit
  /// will re-rank).
  void _reconcilePopupToCaret() {
    final state = _popup.value;
    if (state.isHidden) return;
    final cursor = widget.controller.selection.baseOffset;
    if (cursor < state.tokenStart || cursor > state.tokenStart + 200) {
      _dismissPopup();
      return;
    }
    final text = widget.controller.text;
    final liveTokenStart = _tokenStart(text, cursor);
    if (liveTokenStart != state.tokenStart) {
      _dismissPopup();
    }
  }

  void _showPopup(List<CodeSuggestion> items, int tokenStart, int cursor) {
    final anchor = _caretAnchor(cursor);
    final next = _PopupState(
      items: items,
      selected: 0,
      tokenStart: tokenStart,
      cursor: cursor,
      anchor: anchor,
    );
    _popup.value = next;

    if (_overlay == null) {
      _overlay = OverlayEntry(builder: _buildOverlay);
      Overlay.of(context, rootOverlay: true).insert(_overlay!);
    } else {
      _overlay!.markNeedsBuild();
    }
  }

  /// Hides the popup. When [suppressNext] is true, also swallow the next
  /// auto-trigger — used by Escape so a debounced suggest in flight
  /// doesn't immediately re-open the popup the user just dismissed.
  void _dismissPopup({bool suppressNext = false}) {
    _suggestSeq++;
    _suggestDebounce?.cancel();
    if (_overlay != null) {
      _overlay!.remove();
      _overlay = null;
    }
    if (!_popup.value.isHidden) _popup.value = const _PopupState.hidden();
    if (suppressNext) _suppressNextAutoTrigger = true;
  }

  void _refreshPopupAnchor() {
    final cur = _popup.value;
    if (cur.isHidden) return;
    _popup.value = cur.copyWith(anchor: _caretAnchor(cur.cursor));
    _overlay?.markNeedsBuild();
  }

  void _acceptSuggestion(CodeSuggestion s) {
    final state = _popup.value;
    if (state.isHidden) return;
    final t = widget.controller.text;
    final before = t.substring(0, state.tokenStart);
    // Replace through to the *current* caret, not the cursor snapshot
    // captured when the popup opened — the user may have typed extra
    // characters between popup-show and accept.
    final liveCursor = widget.controller.selection.baseOffset.clamp(
      state.tokenStart,
      t.length,
    );
    final after = t.substring(liveCursor);

    // Chained suggestions (keywords, tables, `*`) append a trailing
    // space and re-open the popup for the next slot. Skip the space if
    // the next char is already whitespace so chaining over an existing
    // gap doesn't double up.
    final wantsSpace =
        s.chainNext && (after.isEmpty || !_isSpace(after.codeUnitAt(0)));
    final insert = wantsSpace ? '${s.insertText} ' : s.insertText;

    final newText = '$before$insert$after';
    final caret = state.tokenStart + insert.length;
    _suppressNextAutoTrigger = true;
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: caret),
    );
    _dismissPopup();

    if (s.chainNext) {
      // Re-open after the controller change has fully propagated.
      // `manualTrigger: true` makes the engine treat an empty token as
      // "show me what fits here" instead of bailing out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_focus.hasFocus) return;
        _requestSuggestions(manualTrigger: true);
      });
    }
  }

  bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

  void _movePopup(int delta) {
    final cur = _popup.value;
    if (cur.isHidden || cur.items.isEmpty) return;
    final raw = (cur.selected + delta) % cur.items.length;
    _popup.value = cur.copyWith(
      selected: raw < 0 ? raw + cur.items.length : raw,
    );
    _overlay?.markNeedsBuild();
  }

  void _setPopupSelected(int index) {
    final cur = _popup.value;
    if (cur.isHidden) return;
    if (index < 0 || index >= cur.items.length) return;
    if (cur.selected == index) return;
    _popup.value = cur.copyWith(selected: index);
    _overlay?.markNeedsBuild();
  }

  bool get _popupOpen =>
      !_popup.value.isHidden && _popup.value.items.isNotEmpty;

  // --- Indentation & newlines --------------------------------------------

  /// Soft-tab width — Tab inserts this, Enter copies it, Shift-Tab strips it.
  static const String _indentUnit = '  ';

  /// Writes [text] + [selection] back to the controller in one edit.
  void _writeValue(String text, TextSelection selection) {
    widget.controller.value = TextEditingValue(
      text: text,
      selection: selection,
    );
  }

  /// Tab / Shift-Tab. A plain caret or single-line selection gets a soft
  /// tab dropped in; a selection spanning lines (or any Shift-Tab) shifts
  /// every touched line by one [_indentUnit].
  void _handleTab({required bool dedent}) {
    final value = widget.controller.value;
    final text = value.text;
    final sel = value.selection;
    if (!sel.isValid) return;
    final start = sel.start;
    final end = sel.end;

    if (!dedent && !text.substring(start, end).contains('\n')) {
      _suppressNextAutoTrigger = true;
      _writeValue(
        text.replaceRange(start, end, _indentUnit),
        TextSelection.collapsed(offset: start + _indentUnit.length),
      );
      return;
    }
    _shiftLines(text, start, end, dedent: dedent);
  }

  /// Indents or dedents every line touched by [selStart]..[selEnd],
  /// keeping the selection over the same span of lines.
  void _shiftLines(
    String text,
    int selStart,
    int selEnd, {
    required bool dedent,
  }) {
    final firstLineStart =
        selStart == 0 ? 0 : text.lastIndexOf('\n', selStart - 1) + 1;
    // A selection that ends exactly at a line start shouldn't drag the
    // next line into the shift.
    var scanEnd = selEnd;
    if (scanEnd > selStart && text.codeUnitAt(scanEnd - 1) == 0x0A) {
      scanEnd -= 1;
    }
    var lastLineEnd = text.indexOf('\n', scanEnd);
    if (lastLineEnd < 0) lastLineEnd = text.length;

    final lines = text.substring(firstLineStart, lastLineEnd).split('\n');
    final out = <String>[];
    var firstDelta = 0;
    var totalDelta = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (dedent) {
        var remove = 0;
        while (remove < _indentUnit.length &&
            remove < line.length &&
            line.codeUnitAt(remove) == 0x20) {
          remove++;
        }
        if (remove == 0 && line.isNotEmpty && line.codeUnitAt(0) == 0x09) {
          remove = 1; // strip a hard tab if that's the leading char
        }
        out.add(line.substring(remove));
        if (i == 0) firstDelta = -remove;
        totalDelta -= remove;
      } else {
        out.add('$_indentUnit$line');
        if (i == 0) firstDelta = _indentUnit.length;
        totalDelta += _indentUnit.length;
      }
    }

    final newText =
        text.substring(0, firstLineStart) +
        out.join('\n') +
        text.substring(lastLineEnd);
    if (newText == text) return; // dedent with nothing to strip

    final newStart = (selStart + firstDelta).clamp(
      firstLineStart,
      newText.length,
    );
    final newEnd = (selEnd + totalDelta).clamp(newStart, newText.length);
    _suppressNextAutoTrigger = true;
    _writeValue(
      newText,
      TextSelection(baseOffset: newStart, extentOffset: newEnd),
    );
  }

  /// Enter in the multi-line editor — inserts a newline followed by the
  /// current line's leading whitespace so indentation carries down.
  void _handleNewline() {
    final value = widget.controller.value;
    final text = value.text;
    final sel = value.selection;
    if (!sel.isValid) return;
    final start = sel.start;
    final lineStart =
        start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
    var i = lineStart;
    while (i < start) {
      final c = text.codeUnitAt(i);
      if (c != 0x20 && c != 0x09) break;
      i++;
    }
    final insert = '\n${text.substring(lineStart, i)}';
    _writeValue(
      text.replaceRange(start, sel.end, insert),
      TextSelection.collapsed(offset: start + insert.length),
    );
  }

  // --- Layout helpers -----------------------------------------------------

  /// First word-character offset preceding [cursor], inclusive.
  int _tokenStart(String text, int cursor) {
    var i = cursor;
    while (i > 0 && _isWord(text.codeUnitAt(i - 1))) {
      i--;
    }
    return i;
  }

  bool _isWord(int c) =>
      (c >= 0x30 && c <= 0x39) || // 0-9
      (c >= 0x41 && c <= 0x5A) || // A-Z
      (c >= 0x61 && c <= 0x7A) || // a-z
      c == 0x5F; // _

  /// Pixel offset just below the caret, relative to the editor box. Uses the
  /// same styled span the field paints to honour wrap differences caused by
  /// bold keywords.
  Offset _caretAnchor(int cursor) {
    if (_metricsWidth <= 0) return Offset.zero;
    final upTo = cursor.clamp(0, widget.controller.text.length);

    final span = widget.controller.buildTextSpan(
      context: context,
      style: _bodyStyle,
      withComposing: false,
    );
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
    )..layout(maxWidth: _metricsWidth);
    final caret = tp.getOffsetForCaret(TextPosition(offset: upTo), Rect.zero);
    tp.dispose();

    final x = _effectiveGutterWidth + widget.padding.left + caret.dx;
    final y = widget.padding.top + caret.dy - _scrollOffset;
    return Offset(x, y + _rowH + 4);
  }

  int get _logicalLineCount =>
      '\n'.allMatches(widget.controller.text).length + 1;

  /// Lays out the entire text using the same highlighted [TextSpan] tree the
  /// TextField paints, then reads each logical line's visual top + height
  /// straight off the painter — no rounding through (fontSize * lineHeight),
  /// so gutter digits track the field exactly even when bold keywords push a
  /// row to wrap a glyph earlier. Cached on (text, bodyWidth).
  void _ensureMetrics(BuildContext context, double bodyWidth) {
    if (bodyWidth <= 0) return;
    final text = widget.controller.text;
    if (text == _metricsText && bodyWidth == _metricsWidth) return;

    final span = widget.controller.buildTextSpan(
      context: context,
      style: _bodyStyle,
      withComposing: false,
    );
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
    )..layout(maxWidth: bodyWidth);

    final lines = text.split('\n');
    final topsPx = List<double>.filled(lines.length, 0);
    final heightsPx = List<double>.filled(lines.length, 0);

    var lineStart = 0;
    for (var i = 0; i < lines.length; i++) {
      final off = tp.getOffsetForCaret(
        TextPosition(offset: lineStart),
        Rect.zero,
      );
      topsPx[i] = off.dy;
      lineStart += lines[i].length + 1; // skip the newline
    }

    final totalHeight = tp.height;
    for (var i = 0; i < lines.length; i++) {
      final nextTop = i + 1 < lines.length ? topsPx[i + 1] : totalHeight;
      heightsPx[i] = (nextTop - topsPx[i]).clamp(0, double.infinity);
    }

    _rowHeightPx = tp.preferredLineHeight;
    tp.dispose();

    _metricsText = text;
    _metricsWidth = bodyWidth;
    _lineTopsPx = topsPx;
    _lineHeightsPx = heightsPx;
  }

  // --- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bg = widget.background ?? AppColors.bg;
    final padded = Container(
      color: bg,
      padding: widget.padding,
      child: _buildField(),
    );

    return ClipRect(
      child: CompositedTransformTarget(
        link: _link,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bodyWidth =
                constraints.maxWidth -
                _effectiveGutterWidth -
                widget.padding.left -
                widget.padding.right;
            _ensureMetrics(context, bodyWidth);
            final lines = _logicalLineCount;

            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                if (_hasGutter)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: _effectiveGutterWidth,
                        decoration: BoxDecoration(
                          color: bg,
                          border: Border(
                            right: BorderSide(
                              color: AppColors.hairline,
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                      Expanded(child: padded),
                    ],
                  )
                else
                  padded,
                // Bands paint on top of the body so the near-transparent
                // accent tint shows through; IgnorePointer keeps caret hits
                // flowing to the field.
                for (final band in widget.lineBands) _buildBand(band),
                if (widget.showLineNumbers)
                  for (var i = 0; i < lines; i++) _buildLineNumber(i),
                if (widget.lineIcon != null)
                  for (var i = 0; i < lines; i++) ..._buildLineIcon(i),
                if (widget.controller.text.isEmpty && widget.hintText != null)
                  _buildHint(),
              ],
            );
          },
        ),
      ),
    );
  }

  double _topPx(int logical) {
    if (_lineTopsPx.isEmpty) return 0;
    final clamped = logical.clamp(0, _lineTopsPx.length - 1);
    return _lineTopsPx[clamped];
  }

  double _heightPx(int logical) {
    if (_lineHeightsPx.isEmpty) return _rowHeightPx;
    final clamped = logical.clamp(0, _lineHeightsPx.length - 1);
    final h = _lineHeightsPx[clamped];
    return h > 0 ? h : _rowHeightPx;
  }

  /// Pixel row height for one visual line — falls back to the static
  /// (fontSize * lineHeight) before the painter has been measured.
  double get _rowH => _rowHeightPx > 0 ? _rowHeightPx : _lineBox;

  Widget _buildField() {
    return TextField(
      controller: widget.controller,
      focusNode: _focus,
      scrollController: widget.singleLine ? null : _scroll,
      maxLines: widget.singleLine ? 1 : null,
      minLines: null,
      expands: widget.singleLine ? false : widget.expands,
      cursorColor: AppColors.accent,
      cursorHeight: widget.cursorHeight,
      style: _bodyStyle,
      inputFormatters: widget.inputFormatters,
      textAlignVertical: TextAlignVertical.top,
      decoration: null,
    );
  }

  Widget _buildBand(LineBand band) {
    final start = band.startLine <= band.endLine
        ? band.startLine
        : band.endLine;
    final end = band.startLine <= band.endLine ? band.endLine : band.startLine;
    final top = widget.padding.top + _topPx(start) - _scrollOffset;
    final bottom =
        widget.padding.top + _topPx(end) + _heightPx(end) - _scrollOffset;
    return Positioned(
      left: _effectiveGutterWidth,
      right: 0,
      top: top,
      height: (bottom - top).clamp(0, double.infinity),
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [band.color, Colors.transparent],
              stops: const [0.0, 0.8],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLineNumber(int i) {
    final digitsWidth = _effectiveGutterWidth - widget.iconColumnWidth - 8;
    return Positioned(
      left: 0,
      top: widget.padding.top + _topPx(i) - _scrollOffset,
      width: digitsWidth,
      height: _rowH,
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Text(
          '${i + 1}',
          textAlign: TextAlign.right,
          style: GoogleFonts.jetBrainsMono(
            fontSize: widget.fontSize,
            height: widget.lineHeight,
            color: AppColors.text4,
          ),
        ),
      ),
    );
  }

  Iterable<Widget> _buildLineIcon(int i) sync* {
    final icon = widget.lineIcon!(i);
    if (icon == null) return;
    yield Positioned(
      left: _effectiveGutterWidth - widget.iconColumnWidth - 2,
      top: widget.padding.top + _topPx(i) - _scrollOffset,
      width: widget.iconColumnWidth,
      height: _rowH,
      child: MouseRegion(
        cursor: icon.onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: icon.onTap,
          child: Tooltip(
            message: icon.tooltip ?? '',
            waitDuration: const Duration(milliseconds: 400),
            child: Text.rich(
              TextSpan(
                style: GoogleFonts.jetBrainsMono(
                  fontSize: widget.fontSize,
                  height: widget.lineHeight,
                ),
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: icon.icon,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHint() {
    final style =
        widget.hintStyle ??
        _bodyStyle.copyWith(
          color: AppColors.text4,
          fontStyle: FontStyle.italic,
        );
    return Positioned(
      left: _effectiveGutterWidth + widget.padding.left,
      top: widget.padding.top,
      child: IgnorePointer(child: Text(widget.hintText!, style: style)),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    return ValueListenableBuilder<_PopupState>(
      valueListenable: _popup,
      builder: (context, state, _) {
        if (state.isHidden) return const SizedBox.shrink();
        return Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            offset: state.anchor,
            child: _AutocompletePopup(
              state: state,
              onPick: _acceptSuggestion,
              onHover: _setPopupSelected,
              fontSize: widget.fontSize,
            ),
          ),
        );
      },
    );
  }
}

class _PopupState {
  const _PopupState({
    required this.items,
    required this.selected,
    required this.tokenStart,
    required this.cursor,
    required this.anchor,
  });

  const _PopupState.hidden()
    : items = const [],
      selected = 0,
      tokenStart = 0,
      cursor = 0,
      anchor = Offset.zero;

  final List<CodeSuggestion> items;
  final int selected;
  final int tokenStart;
  final int cursor;
  final Offset anchor;

  bool get isHidden => items.isEmpty;

  _PopupState copyWith({
    List<CodeSuggestion>? items,
    int? selected,
    int? tokenStart,
    int? cursor,
    Offset? anchor,
  }) => _PopupState(
    items: items ?? this.items,
    selected: selected ?? this.selected,
    tokenStart: tokenStart ?? this.tokenStart,
    cursor: cursor ?? this.cursor,
    anchor: anchor ?? this.anchor,
  );
}

class _AutocompletePopup extends StatefulWidget {
  const _AutocompletePopup({
    required this.state,
    required this.onPick,
    required this.onHover,
    required this.fontSize,
  });

  final _PopupState state;
  final ValueChanged<CodeSuggestion> onPick;
  final ValueChanged<int> onHover;
  final double fontSize;

  @override
  State<_AutocompletePopup> createState() => _AutocompletePopupState();
}

class _AutocompletePopupState extends State<_AutocompletePopup> {
  final ScrollController _scroll = ScrollController();
  // Tall enough to clear descenders (`y`, `g`, `p`) and the `_` underscore
  // in monospace identifiers like `created_at` at fontSize 13. The fixed
  // extent powers cheap scroll-to-selected math; if the popup font ever
  // grows past ~14 this needs to grow with it.
  static const double _rowHeight = 26;

  @override
  void didUpdateWidget(covariant _AutocompletePopup old) {
    super.didUpdateWidget(old);
    if (old.state.selected != widget.state.selected ||
        old.state.items.length != widget.state.items.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSelectedVisible());
    }
  }

  void _ensureSelectedVisible() {
    if (!_scroll.hasClients) return;
    final selected = widget.state.selected;
    final top = selected * _rowHeight;
    final bottom = top + _rowHeight;
    final viewportTop = _scroll.offset;
    final viewportBottom = viewportTop + _scroll.position.viewportDimension;
    if (top < viewportTop) {
      _scroll.jumpTo(top);
    } else if (bottom > viewportBottom) {
      _scroll.jumpTo(bottom - _scroll.position.viewportDimension);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final fontSize = widget.fontSize;
    final onPick = widget.onPick;
    // The popup lives in the root overlay. Without TextFieldTapRegion a
    // pointer-down inside it counts as "outside" to the host TextField,
    // which yields focus → our focus listener dismisses the popup before
    // GestureDetector.onTap ever fires → click silently closes the menu
    // instead of accepting the row.
    return TextFieldTapRegion(
      child: Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(
          minWidth: 240,
          maxWidth: 380,
          maxHeight: 260,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: Radii.brSm,
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: Radii.brSm,
          child: ListView.builder(
            controller: _scroll,
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemExtent: _rowHeight,
            itemCount: state.items.length,
            itemBuilder: (context, i) {
              final s = state.items[i];
              final active = i == state.selected;
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => widget.onHover(i),
                onHover: (_) => widget.onHover(i),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPick(s),
                  child: Container(
                    color: active
                        ? AppColors.accentSoft
                        : Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.centerLeft,
                    child: Row(
                    children: [
                      _KindChip(kind: s.kind),
                      const SizedBox(width: 8),
                      if (s.icon != null) ...[
                        Icon(
                          s.icon,
                          size: 11,
                          color: active
                              ? AppColors.accent
                              : AppColors.textMuted,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          s.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: fontSize,
                            color: active
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (s.detail != null) ...[
                        const SizedBox(width: 10),
                        Text(
                          s.detail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.mono(
                            size: fontSize - 1,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      ),
    );
  }
}

/// 14×14 letter chip on the popup's left edge — gives a quick visual
/// indicator of suggestion kind so a list of mixed columns/tables/
/// keywords stays scannable. Letter+colour are the only signal; the
/// font is tiny so it doesn't compete with the suggestion label.
class _KindChip extends StatelessWidget {
  const _KindChip({required this.kind});

  final SuggestionKind kind;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (kind) {
      SuggestionKind.column => ('c', AppColors.accent),
      SuggestionKind.alias => ('a', AppColors.accent),
      SuggestionKind.table => ('t', AppColors.success),
      SuggestionKind.snippet => ('→', AppColors.success),
      SuggestionKind.keyword => ('k', AppColors.textMuted),
    };
    return Container(
      width: 14,
      height: 14,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 9.5,
          height: 1,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
