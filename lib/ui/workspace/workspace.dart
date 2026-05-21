import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/context_menu.dart';
import 'query_editor.dart';
import 'schema_view.dart';
import 'table_view.dart';

/// Center pane: a refined underline-style tab strip over the active tab's
/// content. Tabs follow Linear conventions — a thin accent
/// underline marks the active tab, hover lifts inactive ones subtly.
class Workspace extends StatelessWidget {
  const Workspace({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tab = state.activeTab;

    if (tab == null) {
      return Container(
        color: AppColors.bg,
        child: EmptyState(
          icon: Icons.dataset_outlined,
          title: 'Nothing open',
          message: 'Press ⌘K to jump, or start a new SQL query.',
          action: AppButton(
            label: 'New Query',
            icon: Icons.add,
            primary: true,
            onPressed: state.newQueryTab,
          ),
        ),
      );
    }

    return Container(
      color: AppColors.bg,
      child: Column(
        children: [
          // Isolate the tab strip's compositor layer from the workspace body
          // so scrolling/editing in the active tab doesn't redraw the strip
          // every frame.
          RepaintBoundary(child: _TabStrip(state: state)),
          Expanded(
            // All tabs stay mounted so per-tab state (scroll offset, code
            // editor cursor, query result) survives switching away and back.
            child: IndexedStack(
              index: state.activeTabIndex.clamp(0, state.tabs.length - 1),
              sizing: StackFit.expand,
              children: [for (final t in state.tabs) _content(t)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(WorkspaceTab tab) {
    final key = ValueKey(tab.id);
    return switch (tab) {
      QueryTab() => QueryEditor(key: key, tab: tab),
      TableTab() => TableView(key: key, tab: tab),
      SchemaTab() => SchemaView(key: key, tab: tab),
    };
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.bgDeep),
      child: SizedBox(
        height: 32,
        child: Stack(
          // Force every non-positioned child to top-left, regardless of
          // its intrinsic alignment behavior — without this, a horizontal
          // SingleChildScrollView in a Stack centers its viewport when it
          // can't decide where to anchor.
          alignment: AlignmentDirectional.topStart,
          fit: StackFit.expand,
          children: [
            // 1. Full-width bottom hairline. Active tabs paint a
            //    solid bg fill that covers the rule under them; inactive
            //    tabs stay transparent so the rule reads through.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(height: 1, color: AppColors.border),
            ),
            // 2. Tabs cluster — anchored to the left, sized to its
            //    content, with horizontal scrolling once it overflows.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              right: 0,
              child: Align(
                alignment: Alignment.topLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < state.tabs.length; i++)
                        _Tab(
                          tab: state.tabs[i],
                          active: i == state.activeTabIndex,
                          onTap: () => state.selectTab(i),
                          onClose: () => state.closeTab(state.tabs[i].id),
                          onContextMenu: (pos) => _showTabMenu(
                            context,
                            state: state,
                            tab: state.tabs[i],
                            position: pos,
                            canCloseRight: i < state.tabs.length - 1,
                          ),
                        ),
                      _NewTabButton(onTap: state.newQueryTab),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 32px square at the end of the tab cluster — matches `.new-tab-btn` in
/// the design. The bottom rule is rendered on the button itself so it
/// continues the inactive-tab hairline cleanly.
class _NewTabButton extends StatelessWidget {
  const _NewTabButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'New query  ⌘N',
      waitDuration: const Duration(milliseconds: 350),
      child: Hoverable(
        onTap: onTap,
        builder: (context, hovering) => Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          // No bottom border — the strip paints a full-width hairline
          // behind every tab and this button alike, so the rule continues
          // uninterrupted to the right edge of the window.
          color: hovering ? AppColors.surfaceHover : Colors.transparent,
          child: Icon(
            Icons.add,
            size: 13,
            color: hovering ? AppColors.textPrimary : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

void _showTabMenu(
  BuildContext context, {
  required AppState state,
  required WorkspaceTab tab,
  required Offset position,
  required bool canCloseRight,
}) {
  showContextMenu(
    context,
    globalPosition: position,
    entries: [
      CmItem(
        icon: Icons.close,
        label: 'Close',
        shortcut: '⌘W',
        onTap: () => state.closeTab(tab.id),
      ),
      CmItem(
        icon: Icons.layers_clear_outlined,
        label: 'Close others',
        enabled: state.tabs.length > 1,
        onTap: () => state.closeOtherTabs(tab.id),
      ),
      CmItem(
        icon: Icons.last_page,
        label: 'Close tabs to the right',
        enabled: canCloseRight,
        onTap: () => state.closeTabsToRight(tab.id),
      ),
      const CmDivider(),
      CmItem(
        icon: Icons.delete_sweep_outlined,
        label: 'Close all',
        enabled: state.tabs.isNotEmpty,
        danger: true,
        onTap: state.closeAllTabs,
      ),
    ],
  );
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
    required this.onContextMenu,
  });

  final WorkspaceTab tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final void Function(Offset globalPosition) onContextMenu;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  IconData get _tabIcon => switch (widget.tab) {
    QueryTab() => Icons.terminal,
    SchemaTab() => Icons.data_object,
    TableTab() => Icons.table_rows_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: widget.onTap,
      onSecondaryTapDown: (d) => widget.onContextMenu(d.globalPosition),
      onTertiaryTapUp: (_) => widget.onClose(),
      builder: (context, hovering) {
        final showClose = hovering || widget.active;
        return Container(
          constraints: const BoxConstraints(maxWidth: 200),
          height: 32,
          decoration: BoxDecoration(
            // Active tab paints a solid `bg` fill so the strip's bottom
            // rule (rendered behind every tab) is masked underneath it.
            // Inactive tabs stay transparent so the rule reads through.
            color: widget.active
                ? AppColors.bg
                : (hovering ? const Color(0x06FFFFFF) : Colors.transparent),
            border: Border(
              right: BorderSide(color: AppColors.borderSoft, width: 1),
              top: widget.active
                  ? BorderSide(color: AppColors.accent, width: 1)
                  : BorderSide.none,
            ),
          ),
          padding: const EdgeInsets.only(left: 10, right: 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _tabIcon,
                size: 11,
                color: widget.active ? AppColors.textMuted : AppColors.text4,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.tab.title,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono(
                    size: 11,
                    weight: FontWeight.w500,
                    color: widget.active
                        ? AppColors.textPrimary
                        : (hovering
                              ? AppColors.textSecondary
                              : AppColors.textMuted),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Hoverable(
                onTap: widget.onClose,
                builder: (context, closeHovering) => AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 14,
                  height: 14,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: closeHovering
                        ? AppColors.surfaceHover
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Icon(
                    Icons.close,
                    size: 8,
                    color: showClose
                        ? (closeHovering
                              ? AppColors.textPrimary
                              : AppColors.textMuted)
                        : Colors.transparent,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
