import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/app_theme.dart';
import 'indent.dart' as indent;
import 'metrics.dart';
import 'suggestions/popup_overlay.dart';
import 'suggestions/suggestion.dart';

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

  /// Drives only the gutter / line-icon / band overlay rebuilds; the
  /// field itself doesn't depend on scroll offset.
  final ValueNotifier<double> _scrollOffset = ValueNotifier<double>(0);

  final LineMetrics _metrics = LineMetrics();

  late final PopupOverlay _popup;

  /// Merged listenable for the decoration subtree: gutter line numbers,
  /// line icons, bands, and the empty-text hint all repaint when the
  /// controller's text changes or the scroll offset shifts. The field
  /// itself sits outside this listener — TextField runs its own listener
  /// against the controller, so it doesn't need an outer rebuild.
  late Listenable _decorationsListenable;

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

    _popup = PopupOverlay(
      editingController: widget.controller,
      isFocused: () => _focus.hasFocus,
      isMounted: () => mounted,
      caretAnchor: _caretAnchor,
      tokenStartOf: indent.tokenStart,
      link: _link,
      fontSize: () => widget.fontSize,
      suggest: widget.suggest,
    );

    _decorationsListenable = Listenable.merge([
      widget.controller,
      _scrollOffset,
    ]);
  }

  @override
  void didUpdateWidget(covariant CodeEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onControllerChange);
      widget.controller.addListener(_onControllerChange);
      _decorationsListenable = Listenable.merge([
        widget.controller,
        _scrollOffset,
      ]);
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
    if (old.suggest != widget.suggest) {
      _popup.suggest = widget.suggest;
    }
  }

  @override
  void dispose() {
    _popup.dispose();
    widget.controller.removeListener(_onControllerChange);
    _focus.removeListener(_onFocusChange);
    _focus.onKeyEvent = null;
    if (_ownsFocus) _focus.dispose();
    _scroll.removeListener(_onScroll);
    if (_ownsScroll) _scroll.dispose();
    _scrollOffset.dispose();
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

    final popupCtl = _popup.controller;
    if (popupCtl.isOpen) {
      if (key == LogicalKeyboardKey.arrowDown) {
        popupCtl.move(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        popupCtl.move(-1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        popupCtl.dismiss(suppressNext: true);
        return KeyEventResult.handled;
      }
      // Tab accepts the highlighted suggestion. Enter no longer accepts —
      // it dismisses the popup and falls through to the newline / submit
      // handlers so pressing Return always inserts a line.
      if (noModifier && isTab) {
        final s = popupCtl.popup.value;
        popupCtl.accept(s.items[s.selected]);
        return KeyEventResult.handled;
      }
      if (noModifier && isEnter) {
        popupCtl.dismiss();
      }
    }

    // Manual trigger: Ctrl-Space (and ⌃Space on macOS) opens the popup
    // with the full ranked list for the current context, even if the
    // user hasn't typed an identifier prefix yet.
    if (key == LogicalKeyboardKey.space &&
        hk.isControlPressed &&
        !hk.isMetaPressed &&
        !hk.isAltPressed) {
      popupCtl.requestSuggestions(manualTrigger: true);
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
      _applyEdit(
        indent.handleTab(
          text: widget.controller.text,
          selection: widget.controller.selection,
          dedent: hk.isShiftPressed,
        ),
      );
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
      _applyEdit(
        indent.handleNewlineInsert(
          text: widget.controller.text,
          selection: widget.controller.selection,
        ),
      );
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Writes a pure-edit result back to the controller in one shot. The
  /// resulting controller-change listener would normally schedule a
  /// suggestion request — suppress that one trigger so structural edits
  /// (Tab, Enter) don't reopen the popup.
  void _applyEdit(indent.EditResult result) {
    _popup.controller.suppressNextAutoTrigger();
    widget.controller.value = TextEditingValue(
      text: result.text,
      selection: result.selection,
    );
  }

  void _onScroll() {
    final next = _scroll.hasClients ? _scroll.offset : 0.0;
    if ((next - _scrollOffset.value).abs() > 0.5) {
      _scrollOffset.value = next;
      _popup.controller.refreshAnchor();
    }
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _popup.controller.dismiss();
  }

  void _onControllerChange() {
    widget.onChanged?.call(widget.controller.text);
    _popup.controller.onEditingChanged();
  }

  // --- Layout helpers -----------------------------------------------------

  /// Pixel offset just below the caret, relative to the editor box. Uses the
  /// same styled span the field paints to honour wrap differences caused by
  /// bold keywords.
  Offset _caretAnchor(int cursor) {
    final span = widget.controller.buildTextSpan(
      context: context,
      style: _bodyStyle,
      withComposing: false,
    );
    final caret = _metrics.caretOffset(
      context: context,
      span: span,
      cursor: cursor,
      textLength: widget.controller.text.length,
    );
    if (caret == Offset.zero && _metrics.width <= 0) return Offset.zero;
    final x = _effectiveGutterWidth + widget.padding.left + caret.dx;
    final y = widget.padding.top + caret.dy - _scrollOffset.value;
    return Offset(x, y + _rowH + 4);
  }

  int get _logicalLineCount =>
      '\n'.allMatches(widget.controller.text).length + 1;

  void _ensureMetrics(BuildContext context, double bodyWidth) {
    if (bodyWidth <= 0) return;
    final span = widget.controller.buildTextSpan(
      context: context,
      style: _bodyStyle,
      withComposing: false,
    );
    _metrics.ensure(
      context: context,
      span: span,
      text: widget.controller.text,
      bodyWidth: bodyWidth,
    );
  }

  // --- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bg = widget.background ?? AppColors.bg;
    _popup.attach(context);

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

            // Built once per layout pass — both the gutter-and-field row
            // and the bare-padded variant share the same Widget instance,
            // so Element reuse keeps the TextField from rebuilding on
            // scroll / text-driven decoration repaints.
            final padded = Container(
              color: bg,
              padding: widget.padding,
              child: _buildField(),
            );
            final fieldRow = _hasGutter
                ? Row(
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
                : padded;

            return ListenableBuilder(
              listenable: _decorationsListenable,
              builder: (context, _) {
                _ensureMetrics(context, bodyWidth);
                final lines = _logicalLineCount;
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    fieldRow,
                    // Bands paint on top of the body so the near-transparent
                    // accent tint shows through; IgnorePointer keeps caret
                    // hits flowing to the field.
                    for (final band in widget.lineBands) _buildBand(band),
                    if (widget.showLineNumbers)
                      for (var i = 0; i < lines; i++) _buildLineNumber(i),
                    if (widget.lineIcon != null)
                      for (var i = 0; i < lines; i++) ..._buildLineIcon(i),
                    if (widget.controller.text.isEmpty &&
                        widget.hintText != null)
                      _buildHint(),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  double _topPx(int logical) => _metrics.topPx(logical);

  double _heightPx(int logical) => _metrics.heightPx(logical);

  /// Pixel row height for one visual line — falls back to the static
  /// (fontSize * lineHeight) before the painter has been measured.
  double get _rowH => _metrics.rowHeight > 0 ? _metrics.rowHeight : _lineBox;

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
    final top = widget.padding.top + _topPx(start) - _scrollOffset.value;
    final bottom =
        widget.padding.top +
        _topPx(end) +
        _heightPx(end) -
        _scrollOffset.value;
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
      top: widget.padding.top + _topPx(i) - _scrollOffset.value,
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
      top: widget.padding.top + _topPx(i) - _scrollOffset.value,
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
}
