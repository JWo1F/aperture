import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Thin draggable separator. The visible hairline is 1px (matches existing
/// dividers) but the hit target spans [thickness] px so it's comfortable to
/// grab without redesigning surrounding layout.
///
/// [axis] is the axis along which the *handle* runs — `vertical` for a column
/// divider that resizes horizontally, `horizontal` for a row divider that
/// resizes vertically.
///
/// Drag math is anchored: [onDragStart] is called once when a drag begins,
/// and [onDragUpdate] is called with the *cumulative* pointer offset since
/// that start. The parent captures its current pane size on start and adds
/// the cumulative offset on every update, so values that clamp out-of-range
/// stay clamped until the pointer crosses the original start position —
/// dragging past the window edge can't silently "bank" extra movement.
class ResizeHandle extends StatefulWidget {
  const ResizeHandle({
    super.key,
    required this.axis,
    required this.onDragStart,
    required this.onDragUpdate,
    this.thickness = 6,
  });

  final Axis axis;
  final VoidCallback onDragStart;
  final void Function(double cumulativeDelta) onDragUpdate;
  final double thickness;

  @override
  State<ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<ResizeHandle> {
  bool _hovering = false;
  bool _dragging = false;
  double _startCoord = 0;

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

    void start(DragStartDetails d) {
      setState(() => _dragging = true);
      _startCoord = isVertical ? d.globalPosition.dx : d.globalPosition.dy;
      widget.onDragStart();
    }

    void update(DragUpdateDetails d) {
      final cur = isVertical ? d.globalPosition.dx : d.globalPosition.dy;
      widget.onDragUpdate(cur - _startCoord);
    }

    void end(_) => setState(() => _dragging = false);

    return MouseRegion(
      cursor: cursor,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: isVertical ? start : null,
        onHorizontalDragUpdate: isVertical ? update : null,
        onHorizontalDragEnd: isVertical ? end : null,
        onVerticalDragStart: isVertical ? null : start,
        onVerticalDragUpdate: isVertical ? null : update,
        onVerticalDragEnd: isVertical ? null : end,
        child: SizedBox(
          width: isVertical ? widget.thickness : null,
          height: isVertical ? null : widget.thickness,
          child: Center(child: hairline),
        ),
      ),
    );
  }
}
