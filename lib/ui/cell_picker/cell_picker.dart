import 'package:flutter/material.dart';

import '../../state/workspace_tab.dart';
import 'kinds.dart';
import 'panel.dart';
import 'target.dart';

export 'target.dart' show CellEditTarget;

/// Opens an overlay editor anchored to the cell's top-left corner. The shape
/// of the picker depends on the value type — text grows multi-line, JSON gets
/// syntax highlighting + room, booleans become a true / false / NULL strip,
/// dates show a calendar, times an editable HH:MM:SS line, datetimes both.
///
/// NULL / Default are hidden when the column metadata forbids them (via
/// [CellEditTarget.canBeNull] / [CellEditTarget.hasDefault]).
void showCellPicker(
  BuildContext context, {
  required Rect anchorRect,
  required CellEditTarget target,
  required ValueChanged<CellEditValue> onCommit,
  VoidCallback? onRevert,
}) {
  final kind = kindFor(target.originalValue, target.columnDataType);
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  void close() {
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => _PickerOverlay(
      kind: kind,
      anchorRect: anchorRect,
      target: target,
      onCommit: (value) {
        close();
        onCommit(value);
      },
      onRevert: onRevert == null
          ? null
          : () {
              close();
              onRevert();
            },
      onClose: close,
    ),
  );

  overlay.insert(entry);
}

/// Full-window overlay that places the [Panel] near the anchor cell and
/// dismisses on outside click / secondary-click.
class _PickerOverlay extends StatelessWidget {
  const _PickerOverlay({
    required this.kind,
    required this.anchorRect,
    required this.target,
    required this.onCommit,
    required this.onRevert,
    required this.onClose,
  });

  final Kind kind;
  final Rect anchorRect;
  final CellEditTarget target;
  final ValueChanged<CellEditValue> onCommit;
  final VoidCallback? onRevert;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    var x = anchorRect.left;
    var y = anchorRect.top;
    final w = kind.size.width;
    final h = kind.size.height;
    if (x + w + 8 > media.width) x = media.width - w - 8;
    if (y + h + 8 > media.height) y = media.height - h - 8;
    if (x < 8) x = 8;
    if (y < 8) y = 8;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            onSecondaryTap: onClose,
          ),
        ),
        Positioned(
          left: x,
          top: y,
          width: w,
          height: h,
          child: Panel(
            kind: kind,
            target: target,
            onCommit: onCommit,
            onRevert: onRevert,
            onClose: onClose,
          ),
        ),
      ],
    );
  }
}
