import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../widgets/resize_handle.dart';

/// Captures the sidebar's current width on drag start so updates resolve
/// as `start + cumulative`. The start value lives in State so it survives
/// the rebuilds that fire on every `setSidebarWidth` call mid-drag.
class SidebarResizeHandle extends StatefulWidget {
  const SidebarResizeHandle({super.key, required this.state});

  final AppState state;

  @override
  State<SidebarResizeHandle> createState() => _SidebarResizeHandleState();
}

class _SidebarResizeHandleState extends State<SidebarResizeHandle> {
  double _startWidth = 0;

  @override
  Widget build(BuildContext context) {
    return ResizeHandle(
      axis: Axis.vertical,
      onDragStart: () => _startWidth = widget.state.preferences.sidebarWidth,
      onDragUpdate: (dx) =>
          widget.state.preferences.setSidebarWidth(_startWidth + dx),
    );
  }
}

class LogResizeHandle extends StatefulWidget {
  const LogResizeHandle({super.key, required this.state});

  final AppState state;

  @override
  State<LogResizeHandle> createState() => _LogResizeHandleState();
}

class _LogResizeHandleState extends State<LogResizeHandle> {
  double _startWidth = 0;

  @override
  Widget build(BuildContext context) {
    return ResizeHandle(
      axis: Axis.vertical,
      onDragStart: () => _startWidth = widget.state.preferences.logPanelWidth,
      onDragUpdate: (dx) =>
          widget.state.preferences.setLogPanelWidth(_startWidth - dx),
    );
  }
}
