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

class Workspace extends StatelessWidget {
  const Workspace({super.key});

  @override
  Widget build(BuildContext context) {
    final tabsKey = context.select<AppState, String>(
      (s) => s.tabs.map((t) => t.id).join('|'),
    );
    final activeIndex = context.select<AppState, int>((s) => s.activeTabIndex);

    if (tabsKey.isEmpty) {
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
            onPressed: context.read<AppState>().newQueryTab,
          ),
        ),
      );
    }

    final tabs = context.read<AppState>().tabs;
    return Container(
      color: AppColors.bg,
      child: Column(
        children: [
          const RepaintBoundary(child: _TabStrip()),
          Expanded(
            child: IndexedStack(
              index: activeIndex.clamp(0, tabs.length - 1),
              sizing: StackFit.expand,
              children: [for (final t in tabs) _content(t)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(WorkspaceTab tab) {
    return ListenableBuilder(
      key: ValueKey(tab.id),
      listenable: tab,
      builder: (_, _) => switch (tab) {
        QueryTab() => QueryEditor(tab: tab),
        TableTab() => TableView(tab: tab),
        SchemaTab() => SchemaView(tab: tab),
      },
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip();

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final tabs = state.tabs;
    final activeIndex = context.select<AppState, int>((s) => s.activeTabIndex);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: SizedBox(
        height: AppLayout.tabHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < tabs.length; i++)
                        ListenableBuilder(
                          listenable: tabs[i],
                          builder: (_, _) => _Tab(
                            tab: tabs[i],
                            active: i == activeIndex,
                            onTap: () => state.selectTab(i),
                            onClose: () => state.closeTab(tabs[i].id),
                            onContextMenu: (pos) => _showTabMenu(
                              context,
                              state: state,
                              tab: tabs[i],
                              position: pos,
                              canCloseRight: i < tabs.length - 1,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _NewTabButton(onTap: state.newQueryTab),
            ],
          ),
        ),
      ),
    );
  }
}

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
        builder: (context, hovering) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hovering ? AppColors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: hovering ? AppColors.borderSoft : Colors.transparent,
                width: 0.5,
              ),
            ),
            child: Icon(
              Icons.add_rounded,
              size: 14,
              color: hovering ? AppColors.textPrimary : AppColors.textMuted,
            ),
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

/// A single tab — a floating pill on the strip. Identity comes from a
/// type-colored status dot (indigo / emerald / amber-purple), not an
/// icon, and the active tab "lifts" with a [AppColors.surface] fill and
/// hairline border. The dot does extra duty: it pulses when the tab is
/// busy (running query / loading page / applying edits) and grows into
/// a warn-colored ring when a TableTab has unsaved cell edits.
///
/// There is no per-tab close button — middle-click, ⌘W, and the
/// right-click menu cover closing.
class _Tab extends StatelessWidget {
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

  Color _typeColor() => switch (tab) {
    QueryTab() => AppColors.accent,
    TableTab() => AppColors.success,
    SchemaTab() => AppColors.tDate,
  };

  bool get _busy => switch (tab) {
    QueryTab(running: final r) => r,
    TableTab(loading: final l, applying: final a) => l || a,
    SchemaTab(loading: final l) => l,
  };

  bool get _dirty => switch (tab) {
    TableTab(hasEdits: final e) => e,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      onSecondaryTapDown: (d) => onContextMenu(d.globalPosition),
      onTertiaryTapUp: (_) => onClose(),
      builder: (context, hovering) {
        final pillFill = active
            ? AppColors.surface
            : (hovering
                  ? Color.alphaBlend(
                      AppColors.surfaceHover.withValues(alpha: 0.55),
                      AppColors.bgDeep,
                    )
                  : Colors.transparent);
        final borderColor = active
            ? AppColors.borderSoft
            : Colors.transparent;
        final labelColor = active
            ? AppColors.textPrimary
            : (hovering ? AppColors.textSecondary : AppColors.textMuted);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220, minWidth: 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: pillFill,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: borderColor, width: 0.5),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StatusDot(
                    color: _typeColor(),
                    active: active,
                    busy: _busy,
                    dirty: _dirty,
                  ),
                  const SizedBox(width: 9),
                  Flexible(child: _TabLabel(tab: tab, color: labelColor, active: active)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The label. For SchemaTab, the trailing `· schema` is rendered in a
/// muted tone so the table name stays primary.
class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.tab, required this.color, required this.active});

  final WorkspaceTab tab;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final weight = active ? FontWeight.w600 : FontWeight.w500;
    final base = AppTheme.ui(
      size: 12.5,
      weight: weight,
      color: color,
      letterSpacing: -0.2,
    );

    if (tab is SchemaTab) {
      final t = tab as SchemaTab;
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: t.table.name, style: base),
            TextSpan(
              text: '  schema',
              style: base.copyWith(
                color: color.withValues(alpha: 0.55),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      );
    }

    return Text(
      tab.title,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      style: base,
    );
  }
}

/// The little circle. Dual-purpose: identifies tab type by color, and
/// animates to signal busy/dirty states without stealing attention.
class _StatusDot extends StatefulWidget {
  const _StatusDot({
    required this.color,
    required this.active,
    required this.busy,
    required this.dirty,
  });

  final Color color;
  final bool active;
  final bool busy;
  final bool dirty;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.busy) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _StatusDot old) {
    super.didUpdateWidget(old);
    if (widget.busy && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.busy && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = widget.dirty
        ? AppColors.warn
        : (widget.active ? widget.color : widget.color.withValues(alpha: 0.55));

    return SizedBox(
      width: 14,
      height: 14,
      child: Center(
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final pulse = widget.busy ? _pulse.value : 0.0;
            return Stack(
              alignment: Alignment.center,
              children: [
                if (widget.busy)
                  Container(
                    width: 6 + pulse * 8,
                    height: 6 + pulse * 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColor.withValues(alpha: 0.18 * (1 - pulse)),
                    ),
                  ),
                if (widget.dirty)
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: dotColor, width: 1.2),
                    ),
                  ),
                Container(
                  width: widget.dirty ? 4 : 6,
                  height: widget.dirty ? 4 : 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                    boxShadow: widget.active
                        ? [
                            BoxShadow(
                              color: dotColor.withValues(alpha: 0.35),
                              blurRadius: 5,
                            ),
                          ]
                        : null,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
