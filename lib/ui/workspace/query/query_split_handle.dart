import 'package:flutter/material.dart';

import '../../../state/app_globals.dart';
import '../../widgets/resize_handle.dart';

/// Drag handle between the editor and the results pane.
///
/// Captures the starting fraction and the available height at drag start so
/// the new fraction is computed against fixed anchors — without this,
/// dragging past the clamp lets cumulative motion silently "bank" and the
/// pane jumps back on direction reversal.
class QuerySplitHandle extends StatefulWidget {
  const QuerySplitHandle({
    super.key,
    required this.available,
    required this.handleHeight,
  });

  final double available;
  final double handleHeight;

  @override
  State<QuerySplitHandle> createState() => _QuerySplitHandleState();
}

class _QuerySplitHandleState extends State<QuerySplitHandle> {
  double _startFraction = 0;
  double _startAvailable = 0;

  @override
  Widget build(BuildContext context) {
    final store = appState.store;
    return ResizeHandle(
      axis: Axis.horizontal,
      thickness: widget.handleHeight,
      onDragStart: () {
        _startFraction = store.queryResultsFraction;
        _startAvailable = widget.available;
      },
      onDragUpdate: (dy) {
        if (_startAvailable <= 0) return;
        store.setQueryResultsFraction(_startFraction - dy / _startAvailable);
      },
    );
  }
}
