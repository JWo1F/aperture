import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';
import 'suggestions/popup_overlay.dart';
import 'suggestions/suggestion.dart';
import 'token.dart';

/// A single-line, highlighted SQL input with an inline autocomplete popup —
/// the table view's clause bars. Multi-line code lives in `re_editor`.
///
/// Enter submits; with the popup open, ↑/↓ move, Tab accepts, Esc closes,
/// and Ctrl-Space asks for suggestions without a typed prefix.
class CodeField extends StatefulWidget {
  const CodeField({
    super.key,
    required this.controller,
    this.focusNode,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.fontSize = 13,
    this.cursorHeight,
    this.background,
    this.hintText,
    this.hintStyle,
    this.suggest,
    this.onSubmit,
  });

  /// Any [TextEditingController]; pass a [CodeEditorController] when you
  /// want highlight tinting via the `highlight` package grammar.
  final TextEditingController controller;
  final FocusNode? focusNode;
  final EdgeInsets padding;
  final double fontSize;
  final double? cursorHeight;
  final Color? background;
  final String? hintText;
  final TextStyle? hintStyle;
  final CodeSuggestProvider? suggest;
  final VoidCallback? onSubmit;

  @override
  State<CodeField> createState() => _CodeFieldState();
}

class _CodeFieldState extends State<CodeField> {
  late FocusNode _focus;
  bool _ownsFocus = false;
  final LayerLink _link = LayerLink();

  late final PopupOverlay _popup;

  TextStyle get _bodyStyle => TextStyle(
    fontFamily: AppTheme.monoFamily,
    fontSize: widget.fontSize,
    height: 1.45,
    color: AppColors.textPrimary,
  );

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? FocusNode();
    _ownsFocus = widget.focusNode == null;
    _focus.onKeyEvent = _onFocusKey;
    widget.controller.addListener(_onControllerChange);
    _focus.addListener(_onFocusChange);

    _popup = PopupOverlay(
      editingController: widget.controller,
      isFocused: () => _focus.hasFocus,
      isMounted: () => mounted,
      // The popup opens at the field's origin, not under the caret.
      caretAnchor: (_) => Offset.zero,
      tokenStartOf: tokenStart,
      link: _link,
      fontSize: () => widget.fontSize,
      suggest: widget.suggest,
    );
  }

  @override
  void didUpdateWidget(covariant CodeField old) {
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
      // Tab accepts the highlighted suggestion; Enter dismisses the popup
      // and falls through to submit.
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

    if (widget.onSubmit != null && noModifier && isEnter) {
      widget.onSubmit!();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _popup.controller.dismiss();
  }

  void _onControllerChange() {
    _popup.controller.onEditingChanged();
  }

  @override
  Widget build(BuildContext context) {
    _popup.attach(context);
    return ClipRect(
      child: CompositedTransformTarget(
        link: _link,
        child: Container(
          color: widget.background ?? AppColors.bg,
          padding: widget.padding,
          child: Stack(
            children: [
              TextField(
                controller: widget.controller,
                focusNode: _focus,
                maxLines: 1,
                cursorColor: AppColors.accent,
                cursorHeight: widget.cursorHeight,
                style: _bodyStyle,
                textAlignVertical: TextAlignVertical.top,
                decoration: null,
              ),
              ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) =>
                    widget.controller.text.isEmpty && widget.hintText != null
                    ? IgnorePointer(
                        child: Text(
                          widget.hintText!,
                          style:
                              widget.hintStyle ??
                              _bodyStyle.copyWith(
                                color: AppColors.text4,
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
