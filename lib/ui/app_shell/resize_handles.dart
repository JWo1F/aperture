import 'package:flutter/material.dart';

import '../../state/app_globals.dart';
import '../widgets/resize_handle.dart';

/// Captures the sidebar's current width on drag start so updates resolve
/// as `start + cumulative`. The start value lives in State so it survives
/// the rebuilds that fire on every `setSidebarWidth` call mid-drag.
class SidebarResizeHandle extends StatefulWidget {
  const SidebarResizeHandle({super.key});

  @override
  State<SidebarResizeHandle> createState() => _SidebarResizeHandleState();
}

class _SidebarResizeHandleState extends State<SidebarResizeHandle> {
  double _startWidth = 0;

  @override
  Widget build(BuildContext context) {
    final store = appState.store;
    return ResizeHandle(
      axis: Axis.vertical,
      onDragStart: () => _startWidth = store.sidebarWidth,
      onDragUpdate: (dx) => store.setSidebarWidth(_startWidth + dx),
    );
  }
}

class LogResizeHandle extends StatefulWidget {
  const LogResizeHandle({super.key});

  @override
  State<LogResizeHandle> createState() => _LogResizeHandleState();
}

class _LogResizeHandleState extends State<LogResizeHandle> {
  double _startWidth = 0;

  @override
  Widget build(BuildContext context) {
    final store = appState.store;
    return ResizeHandle(
      axis: Axis.vertical,
      onDragStart: () => _startWidth = store.logPanelWidth,
      onDragUpdate: (dx) => store.setLogPanelWidth(_startWidth - dx),
    );
  }
}
