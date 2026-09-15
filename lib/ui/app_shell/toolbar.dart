import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_window_utils/macos/ns_window_delegate.dart';
import 'package:macos_window_utils/macos_window_utils.dart';

import '../../state/app_globals.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../command_palette/command_palette.dart';
import '../widgets/common.dart';
import '../widgets/pagebar.dart';
import '../widgets/value_selector.dart';
import 'connection_pill.dart';
import 'toolbar_actions.dart';
import 'toolbar_widgets.dart';

const _windowChannel = MethodChannel('aperture/window');

/// Width reserved on the left of the top toolbar for the macOS traffic-light
/// buttons, which are drawn by the OS on top of our Flutter content.
const double _trafficLightInset = 78;

/// Top toolbar: window-drag surface, navigation + connection controls on
/// the left, ⌘K search and theme/config affordances on the right.
class Toolbar extends StatefulWidget {
  const Toolbar({super.key});

  @override
  State<Toolbar> createState() => _ToolbarState();
}

/// Bridges AppKit's full-screen transitions into [_ToolbarState] so the
/// toolbar can drop the traffic-light inset — macOS hides the traffic
/// lights in full screen, leaving that reserved width as dead space.
class _FullScreenDelegate extends NSWindowDelegate {
  _FullScreenDelegate(this.onChanged);

  final ValueChanged<bool> onChanged;

  @override
  void windowDidEnterFullScreen() {
    onChanged(true);
    super.windowDidEnterFullScreen();
  }

  @override
  void windowDidExitFullScreen() {
    onChanged(false);
    super.windowDidExitFullScreen();
  }
}

class _ToolbarState extends State<Toolbar> {
  bool _fullScreen = false;
  NSWindowDelegateHandle? _delegateHandle;

  @override
  void initState() {
    super.initState();
    _watchFullScreen();
  }

  Future<void> _watchFullScreen() async {
    _delegateHandle = WindowManipulator.addNSWindowDelegate(
      _FullScreenDelegate(_setFullScreen),
    );
    try {
      _setFullScreen(await WindowManipulator.isWindowFullscreened());
    } on MissingPluginException {
      // Tests / non-macOS hosts — no native window to track.
    }
  }

  void _setFullScreen(bool value) {
    if (!mounted || _fullScreen == value) return;
    setState(() => _fullScreen = value);
  }

  @override
  void dispose() {
    _delegateHandle?.removeFromHandler();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // One Selector tuples every reactive bit the toolbar actually paints
    // (brightness, history flags, export-availability for the active tab).
    // The Selector gates rebuilds on `==` of the tuple, so a width drag
    // (different AppStore field) or a cell edit (TabsController forwards
    // every tab-tick) doesn't repaint the toolbar.
    final store = appState.store;
    final tabs = appState.tabsController;
    final history = appState.history;
    return Selector<(bool, bool, AppBrightness, String?, bool)>(
      listenable: Listenable.merge([tabs, history, store]),
      selector: () {
        final tab = tabs.activeTab;
        return (
          history.canGoBack,
          history.canGoForward,
          store.brightness,
          tab?.id,
          exportableResult(tab) != null,
        );
      },
      builder: (context, value) {
        final (canGoBack, canGoForward, brightness, _, canExport) = value;
        return _buildToolbar(
          context: context,
          canGoBack: canGoBack,
          canGoForward: canGoForward,
          brightness: brightness,
          canExport: canExport,
        );
      },
    );
  }

  Widget _buildToolbar({
    required BuildContext context,
    required bool canGoBack,
    required bool canGoForward,
    required AppBrightness brightness,
    required bool canExport,
  }) {
    final store = appState.store;
    final tabs = appState.tabsController;
    // Every child of the row below is fixed-width, and the Stack clips —
    // so once the fixed total exceeds the window, the right-hand controls
    // (theme toggle, reveal-config) were silently cut off rather than
    // overflowing visibly. Snapping Aperture to half a 14" screen was
    // enough. Pick the elastic sizes from the width we actually have.
    final width = MediaQuery.sizeOf(context).width;
    final searchWidth = switch (width) {
      >= 1100 => 220.0,
      >= 940 => 150.0,
      _ => 0.0,
    };
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => _windowChannel.invokeMethod('startDrag'),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          // Match the design's `var(--toolbar)` (bg at 72% alpha) so the
          // app's radial accent halo bleeds through. backdrop-filter blur is
          // not feasible to layer cheaply per-frame; the alpha is the visual
          // tell here, not the blur.
          color: AppColors.bg.withValues(alpha: 0.72),
          border: Border(
            bottom: BorderSide(color: AppColors.hairline, width: 1),
          ),
        ),
        padding: EdgeInsets.only(
          left: _fullScreen ? 4 : _trafficLightInset,
          right: 4,
        ),
        child: Stack(
          children: [
            // Double-tap-to-zoom lives on a background layer *behind* the
            // button row, never as an ancestor of it. A
            // DoubleTapGestureRecognizer on an ancestor keeps the gesture
            // arena open for kDoubleTapTimeout (300ms) on every tap while it
            // waits for a possible second tap — that delay was making every
            // toolbar button feel sluggish. As a Stack sibling it only sees
            // taps that land on the empty toolbar background.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: () => _windowChannel.invokeMethod('toggleZoom'),
              ),
            ),
            Row(
              children: [
                TbIcon(
                  icon: Icons.view_sidebar_outlined,
                  tooltip: 'Toggle sidebar',
                  onPressed: store.toggleSidebar,
                ),
                const TbRail(),
                TbIcon(
                  icon: Icons.arrow_back,
                  tooltip: 'Back  ⌘[',
                  onPressed: canGoBack ? appState.historyBack : null,
                ),
                TbIcon(
                  icon: Icons.arrow_forward,
                  tooltip: 'Forward  ⌘]',
                  onPressed: canGoForward ? appState.historyForward : null,
                ),
                const SizedBox(width: 8),
                const TbGroupRail(),
                const SizedBox(width: 10),
                const ConnectionPill(),
                const SizedBox(width: 8),
                const TbGroupRail(),
                const SizedBox(width: 8),
                TbIcon(
                  icon: Icons.ios_share,
                  tooltip: 'Export…',
                  onPressed: canExport
                      ? () => openExportForActiveTab(context, tabs.activeTab)
                      : null,
                ),
                const Spacer(),
                const _ToolbarTabActions(),
                const SizedBox(width: 6),
                const TbGroupRail(),
                const SizedBox(width: 6),
                // Deliberately a fixed width rather than Flexible: sharing
                // slack with the Spacer above would let the pill drift away
                // from the right edge on a wide window. The width is chosen
                // from the viewport instead, and below the narrowest step
                // the pill gives way to a plain ⌘K button so the palette
                // stays reachable.
                if (searchWidth > 0)
                  SizedBox(
                    width: searchWidth,
                    child: TbSearch(
                      onTap: () => showCommandPalette(context),
                    ),
                  )
                else
                  TbIcon(
                    icon: Icons.search,
                    tooltip: 'Search  ⌘K',
                    onPressed: () => showCommandPalette(context),
                  ),
                const TbRail(),
                TbIcon(
                  icon: brightness == AppBrightness.dark
                      ? Icons.dark_mode_outlined
                      : Icons.light_mode_outlined,
                  tooltip: 'Toggle theme',
                  onPressed: store.toggleBrightness,
                ),
                TbIcon(
                  icon: Icons.folder_outlined,
                  tooltip: 'Reveal config folder in Finder',
                  onPressed: revealConfigFolder,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab-specific actions in the toolbar: pending-edit chip (TableTab only)
/// plus the manual + auto refresh controls (TableTab and QueryTab).
///
/// Reads through a dedicated Selector so a cell-edit on the active tab
/// repaints this cluster (pending count) without re-running the rest of
/// the toolbar selector, and a tab switch swaps the wired callbacks.
class _ToolbarTabActions extends StatelessWidget {
  const _ToolbarTabActions();

  @override
  Widget build(BuildContext context) {
    final tabs = appState.tabsController;
    return Selector<(String?, Type?, int, bool, int?, bool, bool)>(
      listenable: tabs,
      selector: () {
        final tab = tabs.activeTab;
        if (tab is TableTab) {
          return (
            tab.id,
            TableTab,
            tab.pendingOpCount,
            tab.applying,
            tab.autoRefreshInterval?.inMilliseconds,
            tab.loading,
            true,
          );
        }
        if (tab is QueryTab) {
          return (
            tab.id,
            QueryTab,
            0,
            false,
            tab.autoRefreshInterval?.inMilliseconds,
            tab.running,
            tab.lastRunSql != null,
          );
        }
        return (tab?.id, tab?.runtimeType, 0, false, null, false, false);
      },
      builder: (context, _) {
        final tab = tabs.activeTab;
        if (tab is TableTab) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TbPendingChip(tab: tab),
              const SizedBox(width: 6),
              RefreshDropdown(
                interval: tab.autoRefreshInterval,
                busy: tab.loading,
                canRefresh: !tab.loading,
                onManualRefresh: () => tabs.refreshTable(tab),
                onSetInterval: (d) => tabs.setTableAutoRefresh(tab, d),
              ),
            ],
          );
        }
        if (tab is QueryTab) {
          final lastRunSql = tab.lastRunSql;
          return RefreshDropdown(
            interval: tab.autoRefreshInterval,
            busy: tab.running,
            canRefresh: !tab.running && lastRunSql != null,
            onManualRefresh: lastRunSql == null
                ? () {}
                : () => tabs.runQuery(tab, sqlOverride: lastRunSql),
            onSetInterval: (d) => tabs.setQueryAutoRefresh(tab, d),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

/// Pending-edit cluster: a count badge, then independent apply / discard
/// icons. No outer chip — each piece is a discrete toolbar-style button
/// in the same chrome family as [TbIcon] so it blends into the right
/// cluster. The count badge stays visible even at zero, switching to a
/// muted disabled appearance, so a save/edit cycle doesn't reflow the
/// toolbar around it.
class _TbPendingChip extends StatelessWidget {
  const _TbPendingChip({required this.tab});

  final TableTab tab;

  @override
  Widget build(BuildContext context) {
    final count = tab.pendingOpCount;
    final busy = tab.applying;
    final hasPending = count > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PendingBadge(
          count: count,
          onTap: hasPending ? () => showPendingForTab(context, tab) : null,
        ),
        const SizedBox(width: 2),
        _PendingAction(
          icon: Icons.check,
          tooltip: 'Apply pending edits',
          busy: busy,
          onTap: hasPending && !busy
              ? () => applyEditsForTab(tab)
              : null,
        ),
        _PendingAction(
          icon: Icons.close,
          tooltip: 'Discard pending edits',
          onTap: hasPending && !busy
              ? () => appState.tabsController.resetTableEdits(tab)
              : null,
        ),
      ],
    );
  }
}

/// Subtle count pill: surface fill, hairline border, mono digits centred.
/// Active state uses [AppColors.textPrimary]; disabled (no pending) dims
/// to a faded textMuted so the badge reads as "nothing to apply" without
/// vanishing.
class _PendingBadge extends StatelessWidget {
  const _PendingBadge({required this.count, required this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: enabled ? 'Review pending edits' : 'No pending edits',
      waitDuration: const Duration(milliseconds: 350),
      child: Hoverable(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onTap: onTap,
        builder: (context, hovering) {
          final Color bg;
          if (enabled && hovering) {
            bg = AppColors.surfaceHover;
          } else if (enabled) {
            bg = AppColors.surface;
          } else {
            bg = AppColors.surface.withValues(alpha: 0.5);
          }
          final Color borderColor = enabled && hovering
              ? AppColors.borderStrong
              : AppColors.border;
          final Color fg = enabled
              ? AppColors.textPrimary
              : AppColors.textMuted.withValues(alpha: 0.45);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            height: 22,
            constraints: const BoxConstraints(minWidth: 26),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: Radii.brSm,
              border: Border.all(color: borderColor),
            ),
            child: Text(
              '$count',
              style: AppTheme.mono(
                size: 11,
                color: fg,
                weight: FontWeight.w600,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Lightweight icon button in the same chrome as [TbIcon] but at 22×22
/// to match the badge height.
class _PendingAction extends StatelessWidget {
  const _PendingAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: Hoverable(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onTap: onTap,
        builder: (context, hovering) {
          final Color fg = enabled
              ? (hovering ? AppColors.textPrimary : AppColors.textMuted)
              : AppColors.textMuted.withValues(alpha: 0.4);
          // Lerp the hover background through a zero-alpha *surfaceHover*
          // instead of Colors.transparent — see CLAUDE.md > Lessons.
          final Color bg = hovering && enabled
              ? AppColors.surfaceHover
              : AppColors.surfaceHover.withValues(alpha: 0);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, borderRadius: Radii.brSm),
            child: busy
                ? SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  )
                : Icon(icon, size: 13, color: fg),
          );
        },
      ),
    );
  }
}
