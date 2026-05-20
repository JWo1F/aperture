import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Thin draggable separator. The visible hairline is 1px (matches existing
/// dividers) but the hit target spans [thickness] px so it's comfortable to
/// grab without redesigning surrounding layout.
///
/// [axis] is the axis along which the *handle* runs — `vertical` for a column
/// divider that resizes horizontally, `horizontal` for a row divider that
/// resizes vertically. Drag deltas are passed to [onDrag] in logical pixels.
class ResizeHandle extends StatefulWidget {
  const ResizeHandle({
    super.key,
    required this.axis,
    required this.onDrag,
    this.thickness = 6,
  });

  final Axis axis;
  final void Function(double delta) onDrag;
  final double thickness;

  @override
  State<ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<ResizeHandle> {
  bool _hovering = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final isVertical = widget.axis == Axis.vertical;
    final cursor = isVertical
        ? SystemMouseCursors.resizeColumn
        : SystemMouseCursors.resizeRow;
    final active = _hovering || _dragging;
    final lineColor = active ? AppColors.accent : AppColors.hairline;

    final hairline = Container(
      width: isVertical ? 1 : double.infinity,
      height: isVertical ? double.infinity : 1,
      color: lineColor,
    );

    return MouseRegion(
      cursor: cursor,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: isVertical
            ? (_) => setState(() => _dragging = true)
            : null,
        onHorizontalDragUpdate: isVertical
            ? (d) => widget.onDrag(d.delta.dx)
            : null,
        onHorizontalDragEnd: isVertical
            ? (_) => setState(() => _dragging = false)
            : null,
        onVerticalDragStart: isVertical
            ? null
            : (_) => setState(() => _dragging = true),
        onVerticalDragUpdate: isVertical
            ? null
            : (d) => widget.onDrag(d.delta.dy),
        onVerticalDragEnd: isVertical
            ? null
            : (_) => setState(() => _dragging = false),
        child: SizedBox(
          width: isVertical ? widget.thickness : null,
          height: isVertical ? null : widget.thickness,
          child: Center(child: hairline),
        ),
      ),
    );
  }
}
