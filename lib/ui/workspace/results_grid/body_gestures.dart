import 'package:flutter/widgets.dart';

import 'selection_controller.dart';

/// Pointer + gesture wiring that bridges raw events on the data area to the
/// grid's selection controller, the cell picker, the context menu, and the
/// hover-expansion overlay. The wiring stays in one place so each call site
/// (drag-select on primary, double-tap to edit, right-click for menu) reads
/// off one widget tree.
class GridBodyGestures extends StatelessWidget {
  const GridBodyGestures({
    super.key,
    required this.selection,
    required this.gridFocus,
    required this.editable,
    required this.cellAt,
    required this.onHover,
    required this.onExit,
    required this.onOpenPicker,
    required this.onOpenMenu,
    required this.child,
  });

  final SelectionController selection;
  final FocusNode gridFocus;
  final bool editable;
  final (int, int)? Function(Offset localPos) cellAt;
  final void Function(Offset localPos) onHover;
  final VoidCallback onExit;
  final void Function(int row, int column) onOpenPicker;
  final void Function(Offset globalPosition, int row, int column) onOpenMenu;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (e) => onHover(e.localPosition),
      onExit: (_) => onExit(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          // The expansion is left up — a click selects the cell, it shouldn't
          // collapse back to one column.
          final cell = cellAt(e.localPosition);
          if (cell == null) return;
          selection.beginPointer(cell.$1, cell.$2);
          if (!gridFocus.hasFocus) {
            gridFocus.requestFocus();
          }
        },
        onPointerMove: (e) {
          if (!selection.isDragging) return;
          final cell = cellAt(e.localPosition);
          if (cell == null) return;
          selection.extendDrag(cell.$1, cell.$2);
        },
        onPointerUp: (_) => selection.endDrag(),
        onPointerCancel: (_) => selection.endDrag(),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onDoubleTapDown: editable
              ? (d) {
                  final cell = cellAt(d.localPosition);
                  if (cell == null) return;
                  onOpenPicker(cell.$1, cell.$2);
                }
              : null,
          onSecondaryTapDown: (d) {
            final cell = cellAt(d.localPosition);
            if (cell == null) return;
            final (r, c) = cell;
            if (!selection.value.contains(r, c)) {
              selection.selectCell(r, c);
              if (!gridFocus.hasFocus) {
                gridFocus.requestFocus();
              }
            }
            onOpenMenu(d.globalPosition, r, c);
          },
          child: child,
        ),
      ),
    );
  }
}
