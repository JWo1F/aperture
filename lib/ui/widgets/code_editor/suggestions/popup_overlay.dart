import 'package:flutter/widgets.dart';

import 'popup_controller.dart';
import 'popup_state.dart';
import 'popup_widget.dart';
import 'suggestion.dart';

/// Glues the autocomplete state machine ([PopupController]) to its
/// `Overlay` host. Owns the [OverlayEntry] lifecycle so the editor view
/// is not threaded through with overlay bookkeeping — the view just
/// instantiates this, calls [attach] with its `Overlay` context once,
/// forwards key/focus/text events into the exposed controller, and
/// calls [dispose] when done.
///
/// The entry is lazily inserted the first time the popup becomes
/// visible and removed when it goes hidden, so editors that never
/// trigger suggestions never touch the overlay at all.
class PopupOverlay {
  PopupOverlay({
    required TextEditingController editingController,
    required bool Function() isFocused,
    required bool Function() isMounted,
    required Offset Function(int cursor) caretAnchor,
    required int Function(String text, int cursor) tokenStartOf,
    required this.link,
    required this.fontSize,
    CodeSuggestProvider? suggest,
  }) : controller = PopupController(
         editingController: editingController,
         isFocused: isFocused,
         isMounted: isMounted,
         caretAnchor: caretAnchor,
         tokenStartOf: tokenStartOf,
         suggest: suggest,
       ) {
    controller.popup.addListener(_onPopupChange);
  }

  final PopupController controller;
  final LayerLink link;

  /// Lazy getter for the popup's font size — the view captures
  /// `() => widget.fontSize` so a rebuild with a new size is reflected
  /// the next time the overlay paints.
  final double Function() fontSize;

  BuildContext? _overlayContext;
  OverlayEntry? _entry;

  /// Capture the context whose ancestor `Overlay` should host the popup.
  /// Safe to call repeatedly; only the last attached context is used.
  void attach(BuildContext context) {
    _overlayContext = context;
  }

  set suggest(CodeSuggestProvider? provider) =>
      controller.suggest = provider;

  void _onPopupChange() {
    final state = controller.popup.value;
    if (state.isHidden) {
      _removeEntry();
      return;
    }
    final ctx = _overlayContext;
    if (ctx == null) return;
    if (_entry == null) {
      _entry = OverlayEntry(builder: _buildOverlay);
      Overlay.of(ctx, rootOverlay: true).insert(_entry!);
    } else {
      _entry!.markNeedsBuild();
    }
  }

  Widget _buildOverlay(BuildContext context) {
    return ValueListenableBuilder<PopupState>(
      valueListenable: controller.popup,
      builder: (context, state, _) {
        if (state.isHidden) return const SizedBox.shrink();
        return Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: link,
            showWhenUnlinked: false,
            offset: state.anchor,
            child: AutocompletePopup(
              state: state,
              onPick: controller.accept,
              onHover: controller.setSelected,
              fontSize: fontSize(),
            ),
          ),
        );
      },
    );
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  void dispose() {
    _removeEntry();
    controller.popup.removeListener(_onPopupChange);
    controller.dispose();
  }
}
