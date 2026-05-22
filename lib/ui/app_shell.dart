import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_window_utils/macos/ns_window_delegate.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:provider/provider.dart';

import '../models/connection_config.dart';
import '../models/query_result.dart';
import '../models/time_ago.dart';
import '../state/app_state.dart';
import '../state/workspace_tab.dart';
import '../theme/app_theme.dart';
import 'about/about_dialog.dart';
import 'command_palette/command_palette.dart';
import 'connection/connection_dialog.dart';
import 'connection/master_passphrase_setup.dart';
import 'edits/pending_edits_modal.dart';
import 'export/export_dialog.dart';
import 'log/log_panel.dart';
import 'sidebar/sidebar.dart';
import 'widgets/common.dart';
import 'widgets/resize_handle.dart';
import 'workspace/workspace.dart';

const _windowChannel = MethodChannel('dbv/window');

/// Width reserved on the left of the top toolbar for the macOS traffic-light
/// buttons, which are drawn by the OS on top of our Flutter content.
const double _trafficLightInset = 78;

/// Root layout: toolbar on top, sidebar + workspace in the middle, a thin
/// status bar at the bottom.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // ⌘[ / ⌘] are intercepted at the HardwareKeyboard layer so they fire
    // regardless of focus — a TextField inside the active tab would
    // otherwise swallow them via Flutter's default editing shortcuts.
    HardwareKeyboard.instance.addHandler(_onKey);
    // Hand AppState a way to summon the master-passphrase unlock modal
    // when a connect attempt needs decryption.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      state.onPassphraseNeeded = () =>
          showMasterPassphraseUnlock(context, state.masterPassphrase);
    });
  }

  @override
  void didChangeMetrics() {
    // Native window size / position changed — debounce-save the current
    // frame so reopening lands at roughly the same place.
    final state = Provider.of<AppState>(context, listen: false);
    state.preferences.captureWindowFrame();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.inactive ||
        lifecycleState == AppLifecycleState.detached) {
      final state = Provider.of<AppState>(context, listen: false);
      state.preferences.captureWindowFrame();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!HardwareKeyboard.instance.isMetaPressed) return false;
    final state = context.read<AppState>();
    if (event.logicalKey == LogicalKeyboardKey.bracketLeft) {
      state.historyBack();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.bracketRight) {
      state.historyForward();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyQ) {
      // Only intercept when we'd actually warn the user.
      if (state.unappliedEditCount > 0) {
        unawaited(_confirmQuit(state.unappliedEditCount));
        return true;
      }
    }
    return false;
  }

  Future<void> _confirmQuit(int pending) async {
    final keepEditing = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Quit Aperture?',
          style: AppTheme.ui(
            size: 14,
            weight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'You have $pending pending edit${pending == 1 ? '' : 's'}. '
          "Quitting now discards them — they aren't on the server yet.",
          style: AppTheme.ui(color: AppColors.textSecondary),
        ),
        actions: [
          AppButton(
            label: 'Keep editing',
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
          AppButton(
            label: 'Quit anyway',
            danger: true,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
        ],
      ),
    );
    if (keepEditing == false) {
      // User confirmed quit — hand control back to AppKit's terminate.
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pull only the slices the shell layout reacts to. Sidebar drag,
    // log-panel resize, preference changes, tab mutations etc. all stay
    // out of this widget's rebuild path. The sidebar / log-panel /
    // workspace subtrees subscribe to their own state independently.
    final state = context.read<AppState>();
    final status = context.select<AppState, ConnectionStatus>((s) => s.status);
    final sidebarVisible = context.select<AppState, bool>(
      (s) => s.sidebarVisible,
    );
    final logVisible = context.select<AppState, bool>(
      (s) => s.eventLog.isVisible,
    );
    final connected = status == ConnectionStatus.connected;
    final lost = status == ConnectionStatus.lost;
    final showWorkspace = connected || lost;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
              showCommandPalette(context, state),
          const SingleActivator(LogicalKeyboardKey.keyL, meta: true): () =>
              state.eventLog.toggleVisible(),
          if (connected)
            const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () {
              final tab = state.activeTab;
              if (tab is TableTab) state.refreshTable(tab);
            },
        },
        child: FocusScope(
          autofocus: true,
          child: DecoratedBox(
            // Soft accent halo above the toolbar, matching the design's
            // `radial-gradient(1200px 600px at 20% -10%, accent 5%, transparent)`
            // on `.app`. Sits below every surface so the toolbar/sidebar tint
            // takes precedence; only the bare workspace bg ever surfaces it.
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.6, -1.4),
                radius: 1.4,
                colors: [
                  AppColors.accent.withValues(alpha: 0.05),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.6],
              ),
            ),
            child: Column(
              children: [
                const RepaintBoundary(child: _Toolbar()),
                if (lost) _ConnectionLostBanner(state: state),
                Expanded(
                  child: Row(
                    children: [
                      // Wrap the sidebar and workspace in RepaintBoundary so a
                      // repaint in one side doesn't dirty the layer of the
                      // other. Cell-edit repaints in the grid no longer ripple
                      // back through the sidebar's compositor layer, and vice
                      // versa.
                      if (sidebarVisible) ...[
                        const RepaintBoundary(child: Sidebar()),
                        _SidebarResizeHandle(state: state),
                      ],
                      Expanded(
                        child: RepaintBoundary(
                          child: Container(
                            color: AppColors.bg,
                            child: showWorkspace
                                ? const Workspace()
                                : _WelcomePanel(state: state),
                          ),
                        ),
                      ),
                      if (logVisible) _LogResizeHandle(state: state),
                      const RepaintBoundary(child: LogPanel()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Captures the sidebar's current width on drag start so updates resolve
/// as `start + cumulative`. The start value lives in State so it survives
/// the rebuilds that fire on every `setSidebarWidth` call mid-drag.
class _SidebarResizeHandle extends StatefulWidget {
  const _SidebarResizeHandle({required this.state});

  final AppState state;

  @override
  State<_SidebarResizeHandle> createState() => _SidebarResizeHandleState();
}

class _SidebarResizeHandleState extends State<_SidebarResizeHandle> {
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

class _LogResizeHandle extends StatefulWidget {
  const _LogResizeHandle({required this.state});

  final AppState state;

  @override
  State<_LogResizeHandle> createState() => _LogResizeHandleState();
}

class _LogResizeHandleState extends State<_LogResizeHandle> {
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

class _ConnectionLostBanner extends StatefulWidget {
  const _ConnectionLostBanner({required this.state});

  final AppState state;

  @override
  State<_ConnectionLostBanner> createState() => _ConnectionLostBannerState();
}

class _ConnectionLostBannerState extends State<_ConnectionLostBanner> {
  bool _reconnecting = false;

  Future<void> _reconnect() async {
    if (_reconnecting) return;
    setState(() => _reconnecting = true);
    try {
      await widget.state.reconnect();
    } finally {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.state.connectionError;
    return Container(
      color: AppColors.accent.withValues(alpha: 0.10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.link_off, size: 14, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error == null
                  ? 'Connection lost. Your workspace is preserved.'
                  : 'Connection lost: $error',
              style: AppTheme.ui(color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: _reconnecting ? 'Reconnecting…' : 'Reconnect',
            onPressed: _reconnecting ? null : _reconnect,
            primary: true,
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatefulWidget {
  const _Toolbar();

  @override
  State<_Toolbar> createState() => _ToolbarState();
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

class _ToolbarState extends State<_Toolbar> {
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
    // Each reactive bit is a separate selector so the toolbar only
    // rebuilds when one of these actually changes. Brightness, history,
    // pending-edit count and the active tab's exportable result are the
    // only fields driving any visible change in here.
    final state = context.read<AppState>();
    final pending = context.select<AppState, int>((s) => s.unappliedEditCount);
    final canGoBack = context.select<AppState, bool>((s) => s.canGoBack);
    final canGoForward = context.select<AppState, bool>((s) => s.canGoForward);
    final brightness = context.select<AppState, AppBrightness>(
      (s) => s.brightness,
    );
    // Export availability tracks the active tab's id + its result
    // existence. Selecting both as a record means switching tabs or
    // running a query updates this; mere width drags don't.
    final exportKey = context.select<AppState, (String?, bool)>((s) {
      final tab = s.activeTab;
      final result = _exportableResult(tab);
      return (tab?.id, result != null);
    });
    final canExport = exportKey.$2;

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
                _TbIcon(
                  icon: Icons.view_sidebar_outlined,
                  tooltip: 'Toggle sidebar',
                  onPressed: state.toggleSidebar,
                ),
                const _TbRail(),
                _TbIcon(
                  icon: Icons.arrow_back,
                  tooltip: 'Back  ⌘[',
                  onPressed: canGoBack ? state.historyBack : null,
                ),
                _TbIcon(
                  icon: Icons.arrow_forward,
                  tooltip: 'Forward  ⌘]',
                  onPressed: canGoForward ? state.historyForward : null,
                ),
                const SizedBox(width: 8),
                const _TbGroupRail(),
                const SizedBox(width: 10),
                const ConnectionPill(),
                const SizedBox(width: 8),
                const _TbGroupRail(),
                const SizedBox(width: 8),
                _TbIcon(
                  icon: Icons.ios_share,
                  tooltip: 'Export…',
                  onPressed: canExport
                      ? () => _openExportForActiveTab(
                          context,
                          state,
                          state.activeTab,
                        )
                      : null,
                ),
                const Spacer(),
                if (pending > 0) ...[
                  _PendingPill(
                    count: pending,
                    onTap: () => _openPendingForActiveTab(context, state),
                  ),
                  const _TbRail(),
                ],
                // Fixed-width search pill — making it Flexible would force it
                // to compete with the Spacer above for leftover space, so on a
                // wide window the spacer would collapse to half its slack and
                // the search would drift away from the right edge.
                SizedBox(
                  width: 220,
                  child: _TbSearch(
                    onTap: () => showCommandPalette(context, state),
                  ),
                ),
                const _TbRail(),
                _TbIcon(
                  icon: brightness == AppBrightness.dark
                      ? Icons.dark_mode_outlined
                      : Icons.light_mode_outlined,
                  tooltip: 'Toggle theme',
                  onPressed: state.toggleBrightness,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Returns the [QueryResult] the toolbar's Export action would feed to the
/// dialog, or null if [tab] has nothing exportable. Table and query tabs
/// both qualify; lifecycle tabs (schema) never do.
QueryResult? _exportableResult(WorkspaceTab? tab) {
  if (tab is TableTab) return tab.result;
  if (tab is QueryTab) return tab.result;
  return null;
}

void _openExportForActiveTab(
  BuildContext context,
  AppState state,
  WorkspaceTab? tab,
) {
  final timestamp = filenameTimestamp();
  if (tab is TableTab) {
    final result = tab.result;
    if (result == null) return;
    showExportDialog(
      context,
      target: ExportTarget(
        suggestedFilename: '${tab.table.name}_$timestamp.csv',
        currentResult: result,
        fetchAll: () => state.fetchAllForExport(tab),
        totalRowsForAll: tab.totalRows,
      ),
    );
    return;
  }
  if (tab is QueryTab) {
    final result = tab.result;
    if (result == null) return;
    showExportDialog(
      context,
      target: ExportTarget(
        suggestedFilename: 'query_$timestamp.csv',
        currentResult: result,
      ),
    );
  }
}

void _openPendingForActiveTab(BuildContext context, AppState state) {
  final tab = state.activeTab;
  if (tab is TableTab && tab.hasEdits) {
    _showPending(context, state, tab);
    return;
  }
  // Active tab has no edits; surface the first tab that does.
  for (final t in state.tabs) {
    if (t is TableTab && t.hasEdits) {
      state.selectTab(state.tabs.indexOf(t));
      _showPending(context, state, t);
      return;
    }
  }
}

void _showPending(BuildContext context, AppState state, TableTab tab) {
  final statements = state.previewEditStatements(tab);
  final messenger = ScaffoldMessenger.maybeOf(context);
  showPendingEditsModal(
    context,
    statements: statements,
    onApply: () async {
      final error = await state.applyTableEdits(tab);
      if (error != null && messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: AppColors.surfaceAlt,
            content: Text(
              'Apply failed: $error',
              style: AppTheme.mono(size: 11.5, color: AppColors.error),
            ),
          ),
        );
      }
    },
    onRevert: () => state.resetTableEdits(tab),
  );
}

/// Short 1×14 hairline used *within* a toolbar group — e.g. between the
/// sidebar toggle and the back/forward pair. Matches the design's `.rail`.
class _TbRail extends StatelessWidget {
  const _TbRail();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: AppColors.hairline,
    );
  }
}

/// Full-height 1px hairline used *between* toolbar groups — sits flush with
/// the surrounding group padding so it visually divides the run of icons
/// instead of nesting inside one of them. Matches the design's `.tb-rail`.
class _TbGroupRail extends StatelessWidget {
  const _TbGroupRail();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: AppColors.hairline,
    );
  }
}

/// 26×26 ghost icon button used throughout the toolbar.
class _TbIcon extends StatelessWidget {
  const _TbIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: Hoverable(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onTap: onPressed,
        builder: (context, hovering) {
          final Color fg = enabled
              ? (hovering ? AppColors.textPrimary : AppColors.textMuted)
              : AppColors.textMuted.withValues(alpha: 0.4);
          final Color bg = hovering && enabled
              ? AppColors.surfaceHover
              : Colors.transparent;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, borderRadius: Radii.brSm),
            child: Icon(icon, size: 14, color: fg),
          );
        },
      ),
    );
  }
}

/// Accent pill that surfaces the cross-tab pending edit count.
class _PendingPill extends StatelessWidget {
  const _PendingPill({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Open pending edits',
      child: Hoverable(
        onTap: onTap,
        builder: (context, hovering) => Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: hovering
                ? AppColors.accent.withValues(alpha: 0.22)
                : AppColors.accentSoft,
            borderRadius: Radii.brSm,
            border: Border.all(color: AppColors.accentSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.4),
                      blurRadius: 3,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count pending',
                style: AppTheme.ui(
                  size: 11.5,
                  color: AppColors.accent,
                  weight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wide ⌘K search trigger styled as a flat input — surface bg, hairline
/// border, magnifier glyph, hint text, kbd chip.
class _TbSearch extends StatelessWidget {
  const _TbSearch({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Find tables, queries…  ⌘K',
      child: Hoverable(
        onTap: onTap,
        builder: (context, hovering) => Container(
          height: 24,
          padding: const EdgeInsets.only(left: 10, right: 5),
          decoration: BoxDecoration(
            color: hovering ? AppColors.surfaceHover : AppColors.surface,
            borderRadius: Radii.brSm,
            border: Border.all(
              color: hovering ? AppColors.borderStrong : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 12, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Find tables, queries…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.ui(
                    size: 11,
                    color: AppColors.textMuted,
                    weight: FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const _TbKbd(parts: ['⌘', 'K']),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tiny kbd group rendered with the design's surface-2 chip styling.
class _TbKbd extends StatelessWidget {
  const _TbKbd({required this.parts});

  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Container(
            constraints: const BoxConstraints(minWidth: 13, minHeight: 13),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              parts[i],
              // height: 1.0 — AppTheme.ui's 1.35 line box would inflate the
              // chip well past its 13px minHeight.
              style: AppTheme.ui(
                size: 9,
                color: AppColors.textSecondary,
                weight: FontWeight.w500,
              ).copyWith(height: 1.0),
            ),
          ),
        ],
      ],
    );
  }
}

class _ApertureIrisPainter extends CustomPainter {
  _ApertureIrisPainter({required this.accent, required this.dim});

  final Color accent;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final dimStroke = Paint()
      ..color = dim.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 1.5;

    // Outer hex perimeter — six hairlines, dim.
    final hex = Path();
    for (int i = 0; i < 6; i++) {
      final a = (i * 60 - 90) * math.pi / 180;
      final x = cx + r * math.cos(a);
      final y = cy + r * math.sin(a);
      if (i == 0) {
        hex.moveTo(x, y);
      } else {
        hex.lineTo(x, y);
      }
    }
    hex.close();
    canvas.drawPath(hex, dimStroke);

    // Three iris blades — short chords from hex vertices to a small offset
    // around the centre, creating a triangular shutter look without painting
    // every blade (keeps it readable at 18px).
    Offset vertex(int i) {
      final a = (i * 60 - 90) * math.pi / 180;
      return Offset(cx + r * math.cos(a), cy + r * math.sin(a));
    }

    final blade1 = Path()
      ..moveTo(vertex(0).dx, vertex(0).dy)
      ..lineTo(cx + 1.5, cy + 1.5)
      ..lineTo(vertex(2).dx, vertex(2).dy);
    final blade2 = Path()
      ..moveTo(vertex(2).dx, vertex(2).dy)
      ..lineTo(cx - 1.5, cy + 1.5)
      ..lineTo(vertex(4).dx, vertex(4).dy);
    final blade3 = Path()
      ..moveTo(vertex(4).dx, vertex(4).dy)
      ..lineTo(cx, cy - 2)
      ..lineTo(vertex(0).dx, vertex(0).dy);

    canvas.drawPath(blade1, stroke);
    canvas.drawPath(blade2, stroke);
    canvas.drawPath(blade3, stroke);
  }

  @override
  bool shouldRepaint(_ApertureIrisPainter old) =>
      old.accent != accent || old.dim != dim;
}

/// Toolbar identity pill: dot · db icon · conn name · `/` · schema · chev.
/// Tap opens the connection switcher overlay.
class ConnectionPill extends StatefulWidget {
  const ConnectionPill({super.key});

  @override
  State<ConnectionPill> createState() => _ConnectionPillState();
}

class _ConnectionPillState extends State<ConnectionPill> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;

  void _open() {
    if (_entry != null) {
      _close();
      return;
    }
    _entry = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context).insert(_entry!);
  }

  void _close() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  Widget _buildOverlay(BuildContext _) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          offset: const Offset(0, 6),
          showWhenUnlinked: false,
          child: _ConnectionPickerPanel(onClose: _close),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // ConnectionPill reflects connection liveness, the active connection's
    // name, and the schema of the current tab. Subscribe to each slice
    // narrowly so widget-resize ticks and other unrelated notifications
    // don't repaint the pill.
    final status = context.select<AppState, ConnectionStatus>((s) => s.status);
    final connName = context.select<AppState, String?>(
      (s) => s.activeConnection?.name,
    );
    final connColor = context.select<AppState, int?>(
      (s) => s.activeConnection?.color,
    );
    final schema = context.select<AppState, String>(
      (s) => _activeSchema(s) ?? 'public',
    );
    final tint = AppColors.connectionTint(connColor);
    final (Color dot, String connLabel) = switch (status) {
      ConnectionStatus.connected => (
        AppColors.success,
        connName ?? 'connected',
      ),
      ConnectionStatus.connecting => (AppColors.accent, 'connecting…'),
      ConnectionStatus.lost => (AppColors.warning, connName ?? 'lost'),
      ConnectionStatus.error => (AppColors.error, 'no connection'),
      ConnectionStatus.disconnected => (AppColors.textMuted, 'no connection'),
    };

    return CompositedTransformTarget(
      link: _link,
      child: Hoverable(
        onTap: _open,
        builder: (context, hovering) => Container(
          height: 26,
          padding: const EdgeInsets.only(left: 8, right: 8),
          decoration: BoxDecoration(
            color: hovering ? AppColors.surfaceHover : AppColors.surface,
            borderRadius: Radii.brSm,
            border: Border.all(
              color: hovering ? AppColors.borderStrong : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: dot.withValues(alpha: 0.32),
                      blurRadius: 3,
                      spreadRadius: 1.2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.storage_rounded,
                size: 11,
                color: connName != null ? tint : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  connLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.ui(
                    size: 11.5,
                    color: AppColors.textPrimary,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
              if (status == ConnectionStatus.connected) ...[
                const SizedBox(width: 6),
                Text(
                  '/',
                  style: AppTheme.ui(
                    size: 11.5,
                    color: AppColors.text4,
                    weight: FontWeight.w400,
                  ),
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    schema,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.ui(
                      size: 11.5,
                      color: AppColors.textSecondary,
                      weight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Icon(Icons.expand_more, size: 12, color: AppColors.text4),
            ],
          ),
        ),
      ),
    );
  }

  String? _activeSchema(AppState state) {
    final tab = state.activeTab;
    if (tab is TableTab) return tab.table.schema;
    if (tab is SchemaTab) return tab.table.schema;
    return null;
  }
}

class _ConnectionPickerPanel extends StatelessWidget {
  const _ConnectionPickerPanel({required this.onClose});

  final VoidCallback onClose;

  Future<void> _newConnection(BuildContext context) async {
    onClose();
    final state = context.read<AppState>();
    final config = await showConnectionDialog(context);
    if (config == null) return;
    state.addConnection(config);
    await state.connect(config);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final active = state.activeConnection?.id;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 320,
        constraints: const BoxConstraints(maxHeight: 360),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: Radii.brMd,
          border: Border.all(color: AppColors.borderStrong),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.connections.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 14,
                  ),
                  child: Text(
                    'No saved connections yet.',
                    style: AppTheme.ui(size: 11.5, color: AppColors.textMuted),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: state.connections.length,
                    itemBuilder: (_, i) {
                      final c = state.connections[i];
                      return _ConnPickerRow(
                        config: c,
                        active: c.id == active,
                        onTap: () {
                          onClose();
                          if (c.id != active) state.connect(c);
                        },
                      );
                    },
                  ),
                ),
              Divider(height: 9, color: AppColors.hairline),
              Hoverable(
                onTap: () => _newConnection(context),
                builder: (context, hovering) => Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: hovering
                        ? AppColors.surfaceHover
                        : Colors.transparent,
                    borderRadius: Radii.brSm,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.add, size: 13, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Text(
                        'New connection…',
                        style: AppTheme.ui(
                          size: 12,
                          color: AppColors.accent,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ],
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

class _ConnPickerRow extends StatelessWidget {
  const _ConnPickerRow({
    required this.config,
    required this.active,
    required this.onTap,
  });

  final ConnectionConfig config;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = AppColors.connectionTint(config.color);
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? AppColors.accentSoft
              : (hovering ? AppColors.surfaceHover : Colors.transparent),
          borderRadius: Radii.brSm,
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: active ? tint : tint.withValues(alpha: 0.5),
                shape: BoxShape.circle,
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: tint.withValues(alpha: 0.5),
                          blurRadius: 5,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    config.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.mono(
                      size: 12,
                      color: AppColors.textPrimary,
                      weight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    config.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.mono(
                      size: 10.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (active) Icon(Icons.check, size: 13, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}

/// Shown in place of the workspace until a live connection exists. Surfaces
/// the most recently used connections as quick-launch cards.
class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({required this.state});

  final AppState state;

  Future<void> _newConnection(BuildContext context) async {
    final config = await showConnectionDialog(context);
    if (config == null) return;
    state.addConnection(config);
    await state.connect(config);
  }

  @override
  Widget build(BuildContext context) {
    final connecting = state.status == ConnectionStatus.connecting;
    final recents = state.recentConnections;
    final hasAny = state.connections.isNotEmpty;

    return Container(
      color: AppColors.bg,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Padding(
            padding: const EdgeInsets.all(Insets.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _BrandHero(),
                const SizedBox(height: Insets.xl),
                if (connecting)
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  )
                else if (recents.isNotEmpty)
                  _RecentsBlock(
                    recents: recents,
                    onConnect: state.connect,
                    onNew: () => _newConnection(context),
                  )
                else
                  _EmptyBlock(
                    hasAny: hasAny,
                    onNew: () => _newConnection(context),
                  ),
                if (state.status == ConnectionStatus.error &&
                    state.connectionError != null) ...[
                  const SizedBox(height: Insets.xl),
                  _ErrorBox(message: state.connectionError!),
                ],
                const SizedBox(height: Insets.xl),
                Hoverable(
                  onTap: () => showAboutAperture(context),
                  builder: (context, hovering) => Text(
                    'About Aperture',
                    style: AppTheme.mono(
                      size: 10.5,
                      color: hovering
                          ? AppColors.textSecondary
                          : AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 56,
          height: 56,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: Radii.brMd,
              border: Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.all(14),
            child: CustomPaint(
              painter: _ApertureIrisPainter(
                accent: AppColors.accent,
                dim: AppColors.textMuted,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Aperture',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'a postgres viewer',
          style: AppTheme.ui(
            size: 11,
            color: AppColors.textMuted,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _RecentsBlock extends StatelessWidget {
  const _RecentsBlock({
    required this.recents,
    required this.onConnect,
    required this.onNew,
  });

  final List<ConnectionConfig> recents;
  final void Function(ConnectionConfig) onConnect;
  final VoidCallback onNew;

  Future<void> _editConnection(
    BuildContext context,
    ConnectionConfig config,
  ) async {
    final state = context.read<AppState>();
    final updated = await showConnectionDialog(context, existing: config);
    if (updated != null) state.updateConnection(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('RECENT', style: AppTheme.eyebrow()),
            const SizedBox(width: 6),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMuted,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${recents.length}',
              style: AppTheme.eyebrow(color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            for (final c in recents)
              _RecentCard(
                config: c,
                onTap: () => onConnect(c),
                onEdit: () => _editConnection(context, c),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _NewConnectionLink(onTap: onNew),
      ],
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({
    required this.config,
    required this.onTap,
    required this.onEdit,
  });

  final ConnectionConfig config;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final ts = config.lastConnectedAt;
    final tint = AppColors.connectionTint(config.color);
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 260,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: hovering ? AppColors.surfaceHover : AppColors.surface,
          borderRadius: Radii.brMd,
          border: Border.all(
            color: hovering ? tint.withValues(alpha: 0.7) : AppColors.border,
          ),
          boxShadow: hovering
              ? [
                  BoxShadow(
                    color: tint.withValues(alpha: 0.22),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: tint,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    config.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.ui(
                      size: 13,
                      weight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (hovering)
                  Hoverable(
                    cursor: SystemMouseCursors.click,
                    onTap: onEdit,
                    builder: (context, _) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.edit_outlined,
                        size: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  )
                else if (ts != null)
                  Text(
                    timeAgo(ts),
                    style: AppTheme.mono(size: 10, color: AppColors.textMuted),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              config.summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.mono(size: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewConnectionLink extends StatelessWidget {
  const _NewConnectionLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) {
        final fg = hovering ? AppColors.accentHover : AppColors.accent;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 13, color: fg),
            const SizedBox(width: 6),
            Text(
              'New connection',
              style: AppTheme.ui(size: 12, color: fg, weight: FontWeight.w500),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({required this.hasAny, required this.onNew});

  final bool hasAny;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          hasAny
              ? 'Pick a saved connection from the sidebar, or add a new one.'
              : 'Add a PostgreSQL connection to start browsing.',
          textAlign: TextAlign.center,
          style: AppTheme.ui(
            size: 12.5,
            color: AppColors.textMuted,
            weight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: Insets.lg),
        AppButton(
          label: 'New Connection',
          icon: Icons.add_link,
          primary: true,
          onPressed: onNew,
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Container(
        padding: const EdgeInsets.all(Insets.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: Radii.brSm,
          border: Border.all(color: AppColors.error),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 15, color: AppColors.error),
            const SizedBox(width: Insets.sm),
            Flexible(
              child: Text(
                message,
                style: AppTheme.mono(
                  size: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
