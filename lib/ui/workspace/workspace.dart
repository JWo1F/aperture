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
              children: [
                for (final t in state.tabs) _content(t),
              ],
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
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: state.tabs.length,
              itemBuilder: (context, i) {
                final t = state.tabs[i];
                final canCloseRight = i < state.tabs.length - 1;
                return _Tab(
                  tab: t,
                  active: i == state.activeTabIndex,
                  onTap: () => state.selectTab(i),
                  onClose: () => state.closeTab(t.id),
                  onContextMenu: (pos) => _showTabMenu(
                    context,
                    state: state,
                    tab: t,
                    position: pos,
                    canCloseRight: canCloseRight,
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.xs),
            child: IconAction(
              icon: Icons.add,
              tooltip: 'New query',
              onPressed: state.newQueryTab,
            ),
          ),
        ],
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
          constraints: const BoxConstraints(minWidth: 120, maxWidth: 200),
          height: 32,
          decoration: BoxDecoration(
            color: widget.active
                ? AppColors.bg
                : (hovering
                    ? const Color(0x06FFFFFF)
                    : Colors.transparent),
            border: Border(
              right: BorderSide(color: AppColors.borderSoft, width: 1),
              // Accent line sits at the top of the active tab; inactive tabs
              // have no top border so the strip's bottom border is unbroken.
              top: widget.active
                  ? BorderSide(color: AppColors.accent, width: 1)
                  : BorderSide.none,
            ),
          ),
          padding: const EdgeInsets.only(left: 10, right: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _tabIcon,
                size: 13,
                color: widget.active
                    ? AppColors.accent
                    : AppColors.textMuted,
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
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: widget.onClose,
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: Icon(
                      Icons.close,
                      size: 12,
                      color: showClose
                          ? AppColors.textSecondary
                          : Colors.transparent,
                    ),
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
