import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'query_editor.dart';
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
          _TabStrip(state: state),
          Expanded(
            child: tab is QueryTab
                ? QueryEditor(key: ValueKey(tab.id), tab: tab)
                : TableView(
                    key: ValueKey(tab.id),
                    tab: tab as TableTab,
                  ),
          ),
        ],
      ),
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: state.tabs.length,
              itemBuilder: (context, i) => _Tab(
                tab: state.tabs[i],
                active: i == state.activeTabIndex,
                onTap: () => state.selectTab(i),
                onClose: () => state.closeTab(state.tabs[i].id),
              ),
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

class _Tab extends StatefulWidget {
  const _Tab({
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final WorkspaceTab tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isQuery = widget.tab is QueryTab;
    final accentTrack = widget.active
        ? AppColors.accent
        : (_hover ? AppColors.borderStrong : Colors.transparent);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Insets.md),
          decoration: BoxDecoration(
            color: widget.active
                ? AppColors.surface
                : (_hover ? AppColors.surfaceHover : Colors.transparent),
            border: Border(
              bottom: BorderSide(color: accentTrack, width: 2),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isQuery ? Icons.terminal : Icons.table_rows_outlined,
                size: 13,
                color: widget.active
                    ? AppColors.accent
                    : AppColors.textMuted,
              ),
              const SizedBox(width: 7),
              Text(
                widget.tab.title,
                style: AppTheme.ui(
                  size: 12,
                  weight: widget.active ? FontWeight.w600 : FontWeight.w400,
                  color: widget.active
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: Insets.sm),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: widget.onClose,
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: Icon(
                      Icons.close,
                      size: 13,
                      color: _hover || widget.active
                          ? AppColors.textSecondary
                          : Colors.transparent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
