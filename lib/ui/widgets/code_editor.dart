import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:highlight/languages/json.dart' as lang_json;
import 'package:highlight/languages/pgsql.dart' as lang_pgsql;

import '../../theme/app_theme.dart';
import '../../theme/code_theme.dart';

/// A single suggestion shown by the autocomplete popup.
class CodeSuggestion {
  const CodeSuggestion({
    required this.label,
    required this.insertText,
    this.detail,
    this.icon,
  });

  final String label;
  final String insertText;
  final String? detail;
  final IconData? icon;
}

/// Snapshot of the editor at the moment a suggestion is requested.
class SuggestRequest {
  const SuggestRequest({
    required this.text,
    required this.cursor,
    required this.token,
    required this.tokenStart,
  });

  final String text;
  final int cursor;
  final String token;
  final int tokenStart;
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

  // Autocomplete
  final ValueNotifier<_PopupState> _popup =
      ValueNotifier(const _PopupState.hidden());
  OverlayEntry? _overlay;
  int _suggestSeq = 0;
  Timer? _suggestDebounce;

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
    final noModifier = !hk.isShiftPressed &&
        !hk.isMetaPressed &&
        !hk.isAltPressed &&
        !hk.isControlPressed;

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
        _dismissPopup();
        return KeyEventResult.handled;
      }
      if (noModifier &&
          (key == LogicalKeyboardKey.tab ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter)) {
        final s = _popup.value;
        _acceptSuggestion(s.items[s.selected]);
        return KeyEventResult.handled;
      }
    }

    if (widget.singleLine &&
        widget.onSubmit != null &&
        noModifier &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      widget.onSubmit!();
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
    if (widget.suggest != null) _scheduleSuggest();
    if (mounted) setState(() {});
  }

  // --- Autocomplete -------------------------------------------------------

  void _scheduleSuggest() {
    _suggestDebounce?.cancel();
    _suggestDebounce =
        Timer(const Duration(milliseconds: 50), _requestSuggestions);
  }

  Future<void> _requestSuggestions() async {
    if (!mounted || !_focus.hasFocus) return;
    final provider = widget.suggest;
    if (provider == null) return;

    final text = widget.controller.text;
    final cursor = widget.controller.selection.baseOffset;
    if (cursor < 0 ||
        widget.controller.selection.extentOffset != cursor) {
      _dismissPopup();
      return;
    }

    final tokenStart = _tokenStart(text, cursor);
    final token = text.substring(tokenStart, cursor);

    final seq = ++_suggestSeq;
    final res = await provider(SuggestRequest(
      text: text,
      cursor: cursor,
      token: token,
      tokenStart: tokenStart,
    ));
    if (!mounted || seq != _suggestSeq) return;

    if (res.isEmpty) {
      _dismissPopup();
      return;
    }

    _showPopup(res, tokenStart, cursor);
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

  void _dismissPopup() {
    _suggestSeq++;
    if (_overlay != null) {
      _overlay!.remove();
      _overlay = null;
    }
    if (!_popup.value.isHidden) _popup.value = const _PopupState.hidden();
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
    final after = t.substring(state.cursor);
    final newText = '$before${s.insertText}$after';
    final caret = state.tokenStart + s.insertText.length;
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: caret),
    );
    _dismissPopup();
  }

  void _movePopup(int delta) {
    final cur = _popup.value;
    if (cur.isHidden || cur.items.isEmpty) return;
    final raw = (cur.selected + delta) % cur.items.length;
    _popup.value = cur.copyWith(
      selected: raw < 0 ? raw + cur.items.length : raw,
    );
    _overlay?.markNeedsBuild();
  }

  bool get _popupOpen =>
      !_popup.value.isHidden && _popup.value.items.isNotEmpty;

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
      final nextTop =
          i + 1 < lines.length ? topsPx[i + 1] : totalHeight;
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
            final bodyWidth = constraints.maxWidth -
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
    final start = band.startLine <= band.endLine ? band.startLine : band.endLine;
    final end = band.startLine <= band.endLine ? band.endLine : band.startLine;
    final top = widget.padding.top + _topPx(start) - _scrollOffset;
    final bottom = widget.padding.top + _topPx(end) + _heightPx(end) -
        _scrollOffset;
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
    final digitsWidth =
        _effectiveGutterWidth - widget.iconColumnWidth - 8;
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
    final style = widget.hintStyle ??
        _bodyStyle.copyWith(
          color: AppColors.text4,
          fontStyle: FontStyle.italic,
        );
    return Positioned(
      left: _effectiveGutterWidth + widget.padding.left,
      top: widget.padding.top,
      child: IgnorePointer(
        child: Text(widget.hintText!, style: style),
      ),
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
  }) =>
      _PopupState(
        items: items ?? this.items,
        selected: selected ?? this.selected,
        tokenStart: tokenStart ?? this.tokenStart,
        cursor: cursor ?? this.cursor,
        anchor: anchor ?? this.anchor,
      );
}

class _AutocompletePopup extends StatelessWidget {
  const _AutocompletePopup({
    required this.state,
    required this.onPick,
    required this.fontSize,
  });

  final _PopupState state;
  final ValueChanged<CodeSuggestion> onPick;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(
          minWidth: 220,
          maxWidth: 360,
          maxHeight: 260,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: Radii.brSm,
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: Radii.brSm,
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: state.items.length,
            itemBuilder: (context, i) {
              final s = state.items[i];
              final active = i == state.selected;
              return InkWell(
                onTap: () => onPick(s),
                hoverColor: AppColors.surfaceHover,
                child: Container(
                  color: active ? AppColors.accentSoft : Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Row(
                    children: [
                      if (s.icon != null) ...[
                        Icon(
                          s.icon,
                          size: 12,
                          color: active
                              ? AppColors.accent
                              : AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
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
                            fontWeight:
                                active ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (s.detail != null) ...[
                        const SizedBox(width: 10),
                        Text(
                          s.detail!,
                          style: AppTheme.mono(
                            size: fontSize - 1,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
