import 'package:flutter/material.dart';

import '../../state/app_globals.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../../theme/hugeicons.dart';
import '../app_shell/confirm_discard.dart';
import '../widgets/common.dart';
import '../widgets/context_menu.dart';
import '../widgets/value_selector.dart';
import 'query/query_editor.dart';
import 'schema_view.dart';
import 'table_view.dart';
import 'workspace_home.dart';
import '../widgets/command_key.dart';

class Workspace extends StatelessWidget {
  const Workspace({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = appState.tabsController;
    return Selector<(String, int)>(
      listenable: controller,
      selector: () => (
        controller.tabs.map((tab) => tab.id).join('|'),
        controller.activeIndex,
      ),
      builder: (_, value) {
        final (tabsKey, activeIndex) = value;
        if (tabsKey.isEmpty) return const WorkspaceHome();
        final tabs = controller.tabs;
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
      },
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
    final tabsController = appState.tabsController;
    // Depend on the tab set itself, not just the active index — closing a
    // non-active tab leaves activeIndex unchanged, and without this the
    // strip would keep rendering the already-closed tab.
    return Selector<(String, int)>(
      listenable: tabsController,
      selector: () => (
        tabsController.tabs.map((tab) => tab.id).join('|'),
        tabsController.activeIndex,
      ),
      builder: (_, value) {
        final activeIndex = value.$2;
        final tabs = tabsController.tabs;
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
                                onTap: () => tabsController.selectTab(i),
                                onClose: () => _closeGuarded(
                                  context,
                                  closing: [tabs[i]],
                                  noun: 'this tab',
                                  close: () =>
                                      tabsController.closeTab(tabs[i].id),
                                ),
                                onContextMenu: (pos) => _showTabMenu(
                                  context,
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
                  _NewTabButton(onTap: tabsController.newQueryTab),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NewTabButton extends StatelessWidget {
  const _NewTabButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'New query  ${commandLabel('N')}',
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
              color: hovering
                  ? AppColors.surface
                  : AppColors.surface.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: hovering
                    ? AppColors.borderSoft
                    : AppColors.borderSoft.withValues(alpha: 0),
                width: 0.5,
              ),
            ),
            child: Icon(
              Hgi.add01,
              size: 14,
              color: hovering ? AppColors.textPrimary : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Staged mutations across [tabs] — only `TableTab`s carry any.
int _pendingIn(Iterable<WorkspaceTab> tabs) => tabs
    .whereType<TableTab>()
    .fold(0, (n, t) => n + t.pendingOpCount);

/// Runs [close] after confirming, if the tabs it will destroy hold staged
/// edits. Closing a tab disposes it, and its pending mutations go with it —
/// the same loss the quit route has always prompted for.
Future<void> _closeGuarded(
  BuildContext context, {
  required Iterable<WorkspaceTab> closing,
  required String noun,
  required VoidCallback close,
}) async {
  final pending = _pendingIn(closing);
  if (pending > 0) {
    final proceed = await confirmDiscardEdits(
      context,
      pending: pending,
      title: 'Close $noun?',
      action: 'Closing',
      proceedLabel: 'Close anyway',
    );
    if (!proceed) return;
  }
  close();
}

void _showTabMenu(
  BuildContext context, {
  required WorkspaceTab tab,
  required Offset position,
  required bool canCloseRight,
}) {
  final tabsController = appState.tabsController;
  final tabs = tabsController.tabs;
  final anchor = tabs.indexWhere((t) => t.id == tab.id);
  showContextMenu(
    context,
    globalPosition: position,
    entries: [
      CmItem(
        icon: Hgi.cancel01,
        label: 'Close',
        shortcut: commandLabel('W'),
        onTap: () => _closeGuarded(
          context,
          closing: [tab],
          noun: 'this tab',
          close: () => tabsController.closeTab(tab.id),
        ),
      ),
      CmItem(
        icon: Hgi.cancelSquare,
        label: 'Close others',
        enabled: tabs.length > 1,
        onTap: () => _closeGuarded(
          context,
          closing: tabs.where((t) => t.id != tab.id),
          noun: 'the other tabs',
          close: () => tabsController.closeOtherTabs(tab.id),
        ),
      ),
      CmItem(
        icon: Hgi.arrowRightDouble,
        label: 'Close tabs to the right',
        enabled: canCloseRight,
        onTap: () => _closeGuarded(
          context,
          closing: anchor == -1 ? const [] : tabs.skip(anchor + 1),
          noun: 'those tabs',
          close: () => tabsController.closeTabsToRight(tab.id),
        ),
      ),
      const CmDivider(),
      CmItem(
        icon: Hgi.deleteThrow,
        label: 'Close all',
        enabled: tabs.isNotEmpty,
        danger: true,
        onTap: () => _closeGuarded(
          context,
          closing: tabs,
          noun: 'every tab',
          close: tabsController.closeAllTabs,
        ),
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
                  : AppColors.bgDeep.withValues(alpha: 0));
        final borderColor = active
            ? AppColors.borderSoft
            : AppColors.borderSoft.withValues(alpha: 0);
        final labelColor = active
            ? AppColors.textPrimary
            : (hovering ? AppColors.textSecondary : AppColors.textMuted);

        final showClose = hovering || active;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
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
              padding: const EdgeInsets.fromLTRB(10, 3, 4, 3),
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
                  Flexible(child: _TabLabel(tab: tab, color: labelColor)),
                  const SizedBox(width: 6),
                  _CloseButton(visible: showClose, onTap: onClose),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The label. For SchemaTab, the trailing `info` / `ddl` is rendered in a
/// muted tone so the table name stays primary. Font weight stays
/// constant across states — color carries the active/hover signal so
/// neighbouring tabs don't reflow when activation changes.
class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.tab, required this.color});

  final WorkspaceTab tab;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final base = AppTheme.ui(
      size: 12.5,
      weight: FontWeight.w500,
      color: color,
      letterSpacing: -0.2,
    );

    if (tab is SchemaTab) {
      final t = tab as SchemaTab;
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: t.object.name, style: base),
            TextSpan(
              text: t.view == ObjectView.info ? '  info' : '  ddl',
              style: base.copyWith(color: color.withValues(alpha: 0.55)),
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

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: visible ? onTap : null,
      builder: (context, hovering) => AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 16,
        height: 16,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: visible && hovering
              ? AppColors.surfaceHover
              : AppColors.surfaceHover.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          Hgi.cancel01,
          size: 11,
          color: visible
              ? (hovering ? AppColors.textPrimary : AppColors.textMuted)
              : Colors.transparent,
        ),
      ),
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
