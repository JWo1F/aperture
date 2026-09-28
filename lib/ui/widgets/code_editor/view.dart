import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
///
/// [spine] paints a solid 2px rule down the band's left edge, flush against
/// the gutter hairline. The wash alone reads as ambient tint at low alpha;
/// the spine is what makes the block's extent unambiguous.
class LineBand {
  const LineBand({
    required this.startLine,
    required this.endLine,
    required this.color,
    this.spine,
  });

  final int startLine;
  final int endLine;
  final Color color;
  final Color? spine;
}

/// A small, self-contained code editor. Owns the gutter, line numbers, line
/// icons, the highlighted TextField, and an inline autocomplete popup.
///
/// One widget powers the multi-line SQL editor, the single-line clause-bar
/// inputs, and the JSON cell editor — all three share metrics so the same
/// font, padding, and caret rules apply everywhere.
///
/// Multi-line layout: a single outer [SingleChildScrollView] is the only
/// scroll source. The `TextField` itself sits inside a [SizedBox] sized to
/// `metrics.totalHeightPx + padding` with `NeverScrollableScrollPhysics`,
/// so it never owns the scroll — gutter, bands, and field all share one
/// coordinate space inside the scroll content. Caret-follow on keyboard
/// input is wired manually via [_ensureCaretVisible] because the field's
/// own `_showCaretOnScreen` no-ops with frozen physics.
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

  /// Drives the outer [SingleChildScrollView] in multi-line mode. The
  /// field itself never scrolls, so passing a controller here is the
  /// canonical way to observe or drive the editor's scroll position.
  final ScrollController? scrollController;

  final bool showLineNumbers;

  /// Single-line mode disables expanding height, multi-line editing, and the
  /// scroll wrapping. Bare Enter falls through to [onSubmit].
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

  final LineMetrics _metrics = LineMetrics();

  late final PopupOverlay _popup;

  // TextField merges this over the theme's M3 input style (`bodyLarge`), so
  // every field it leaves unset is inherited in the field but not in the
  // `LineMetrics` painter. `letterSpacing` is the one that differs: the
  // inherited 0.5 wrapped long lines earlier in the field than in the
  // metrics. Pinned at the value the editors have always painted with.
  TextStyle get _bodyStyle => TextStyle(
    fontFamily: AppTheme.monoFamily,
    fontSize: widget.fontSize,
    height: widget.lineHeight,
    letterSpacing: 0.5,
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

    if (widget.singleLine && widget.onSubmit != null && noModifier && isEnter) {
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
    _popup.controller.refreshAnchor();
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _popup.controller.dismiss();
  }

  void _onControllerChange() {
    widget.onChanged?.call(widget.controller.text);
    _popup.controller.onEditingChanged();
    if (!widget.singleLine) {
      // Defer until the field has laid out its new content so caret
      // metrics reflect the post-edit state, then bring the caret back
      // into view if the edit pushed it past the viewport edge.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureCaretVisible();
      });
    }
  }

  /// The field has frozen scroll physics, so Flutter's built-in
  /// `RenderEditable._showCaretOnScreen` no-ops. This manual follow runs
  /// after every controller change and scrolls the outer view just
  /// enough to keep the caret inside the viewport with a small margin.
  void _ensureCaretVisible() {
    if (!_scroll.hasClients || !_focus.hasFocus) return;
    final position = _scroll.position;
    final viewportH = position.viewportDimension;
    if (viewportH <= 0) return;
    final cursor = widget.controller.selection.extentOffset;
    if (cursor < 0) return;
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
    final caretTop = widget.padding.top + caret.dy;
    final caretBottom = caretTop + _rowH;
    const margin = 12.0;
    final viewTop = position.pixels;
    final viewBottom = viewTop + viewportH;
    if (caretTop < viewTop + margin) {
      final target = (caretTop - margin).clamp(0.0, position.maxScrollExtent);
      _scroll.jumpTo(target);
    } else if (caretBottom > viewBottom - margin) {
      final target = (caretBottom + margin - viewportH).clamp(
        0.0,
        position.maxScrollExtent,
      );
      _scroll.jumpTo(target);
    }
  }

  // --- Layout helpers -----------------------------------------------------

  /// Pixel offset just below the caret, in the editor's *viewport* frame
  /// (the link target's coordinate space). Subtracts the outer scroll
  /// offset because the popup overlay is anchored to the viewport box,
  /// not the scrolled content.
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
    final scrollOffset = _scroll.hasClients ? _scroll.offset : 0.0;
    final x = _effectiveGutterWidth + widget.padding.left + caret.dx;
    final y = widget.padding.top + caret.dy - scrollOffset;
    return Offset(x, y + _rowH + 4);
  }

  int get _logicalLineCount =>
      '\n'.allMatches(widget.controller.text).length + 1;

  void _ensureMetrics(BuildContext context, double bodyWidth) {
    if (bodyWidth <= 0) return;
    // RenderEditable lays its paragraph out `cursorWidth + 1` narrower than
    // the field to leave room for the caret. Measuring at the full width
    // wraps a line near the edge one row later than the field does; enough
    // of those and the field outgrows the scroll content, grows a scroll of
    // its own, and the last lines fall out of the outer one's reach.
    const caretMargin = 2.0 + 1.0;
    final span = widget.controller.buildTextSpan(
      context: context,
      style: _bodyStyle,
      withComposing: false,
    );
    _metrics.ensure(
      context: context,
      span: span,
      text: widget.controller.text,
      bodyWidth: bodyWidth - caretMargin,
    );
  }

  double _topPx(int logical) => _metrics.topPx(logical);

  double _heightPx(int logical) => _metrics.heightPx(logical);

  /// Pixel row height for one visual line — falls back to the static
  /// (fontSize * lineHeight) before the painter has been measured.
  double get _rowH => _metrics.rowHeight > 0 ? _metrics.rowHeight : _lineBox;

  // --- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bg = widget.background ?? AppColors.bg;
    _popup.attach(context);

    // Single-line mode is a plain padded TextField — no scroll wrap, no
    // gutter, no bands. The field handles its own horizontal scroll for
    // long inputs.
    if (widget.singleLine) {
      return ClipRect(
        child: CompositedTransformTarget(
          link: _link,
          child: Container(
            color: bg,
            padding: widget.padding,
            child: _buildField(),
          ),
        ),
      );
    }

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
            return ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                _ensureMetrics(context, bodyWidth);
                final viewportH = constraints.hasBoundedHeight
                    ? constraints.maxHeight
                    : 0.0;
                final naturalH =
                    widget.padding.top +
                    widget.padding.bottom +
                    (_metrics.totalHeightPx > 0
                        ? _metrics.totalHeightPx
                        : _rowH);
                // The scroll content always fills the viewport so the
                // gutter's hairline border extends past the last line
                // when the document is short.
                final scrollContentH = naturalH > viewportH
                    ? naturalH
                    : viewportH;
                final lines = _logicalLineCount;
                final body = Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        color: bg,
                        padding: widget.padding,
                        child: _buildField(),
                      ),
                    ),
                    for (final band in widget.lineBands) _buildBand(band),
                    if (widget.controller.text.isEmpty &&
                        widget.hintText != null)
                      _buildHint(),
                  ],
                );
                final Widget content = _hasGutter
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildGutter(lines, bg),
                          Expanded(child: body),
                        ],
                      )
                    : body;
                return SingleChildScrollView(
                  controller: _scroll,
                  child: SizedBox(height: scrollContentH, child: content),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildField() {
    return TextField(
      controller: widget.controller,
      focusNode: _focus,
      // Freeze the field's own scroll in multi-line mode — the outer
      // SingleChildScrollView is the only scroll source.
      scrollPhysics: widget.singleLine
          ? null
          : const NeverScrollableScrollPhysics(),
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
    final top = widget.padding.top + _topPx(start);
    final bottom = widget.padding.top + _topPx(end) + _heightPx(end);
    return Positioned(
      left: 0,
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
            border: band.spine == null
                ? null
                : Border(left: BorderSide(color: band.spine!, width: 2)),
          ),
        ),
      ),
    );
  }

  Widget _buildGutter(int lines, Color bg) {
    // Resolved once per build rather than once per line. This runs inside
    // the controller's ListenableBuilder, so on a few-hundred-line script
    // it was a TextStyle allocation per line per
    // keystroke.
    final numberStyle = TextStyle(
      fontFamily: AppTheme.monoFamily,
      fontSize: widget.fontSize,
      height: widget.lineHeight,
      color: AppColors.text4,
    );
    return SizedBox(
      width: _effectiveGutterWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          border: Border(
            right: BorderSide(color: AppColors.hairline, width: 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: widget.padding.top),
            for (var i = 0; i < lines; i++) _buildGutterRow(i, numberStyle),
          ],
        ),
      ),
    );
  }

  /// One gutter cell. Its outer height matches `metrics.heightPx(i)`, so
  /// a wrapped logical line gets the full multi-row span — but the icon
  /// and the number themselves sit in row-height boxes pinned to the top
  /// of that span (matching the first visual row of the line).
  Widget _buildGutterRow(int i, TextStyle numberStyle) {
    final lineIcon = widget.lineIcon?.call(i);
    final h = _metrics.heightPx(i) > 0 ? _metrics.heightPx(i) : _rowH;
    final digitsWidth = _effectiveGutterWidth - widget.iconColumnWidth - 8;
    return SizedBox(
      height: h,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showLineNumbers)
            SizedBox(
              width: digitsWidth,
              height: _rowH,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  '${i + 1}',
                  textAlign: TextAlign.right,
                  style: numberStyle,
                ),
              ),
            ),
          SizedBox(
            width: widget.iconColumnWidth,
            height: _rowH,
            child: lineIcon == null ? null : _buildLineIcon(lineIcon),
          ),
        ],
      ),
    );
  }

  Widget _buildLineIcon(LineIcon icon) {
    return MouseRegion(
      cursor: icon.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: icon.onTap,
        child: Tooltip(
          message: icon.tooltip ?? '',
          waitDuration: const Duration(milliseconds: 400),
          child: Center(child: icon.icon),
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
      left: widget.padding.left,
      top: widget.padding.top,
      child: IgnorePointer(child: Text(widget.hintText!, style: style)),
    );
  }
}
