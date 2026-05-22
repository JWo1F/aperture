import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/event_log.dart';
import '../../state/preferences_controller.dart';
import '../../state/session_controller.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../command_palette/command_palette.dart';
import '../connection/master_passphrase_setup.dart';
import '../log/log_panel.dart';
import '../sidebar/sidebar.dart';
import '../widgets/common.dart';
import '../workspace/workspace.dart';
import 'connection_lost_banner.dart';
import 'resize_handles.dart';
import 'toolbar.dart';
import 'welcome_panel.dart';

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
    final status = context.select<SessionController, ConnectionStatus>(
      (s) => s.status,
    );
    final sidebarVisible = context.select<PreferencesController, bool>(
      (p) => p.sidebarVisible,
    );
    final logVisible = context.select<EventLog, bool>((l) => l.isVisible);
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
                const RepaintBoundary(child: Toolbar()),
                if (lost) ConnectionLostBanner(state: state),
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
                        SidebarResizeHandle(state: state),
                      ],
                      Expanded(
                        child: RepaintBoundary(
                          child: Container(
                            color: AppColors.bg,
                            child: showWorkspace
                                ? const Workspace()
                                : WelcomePanel(state: state),
                          ),
                        ),
                      ),
                      if (logVisible) LogResizeHandle(state: state),
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
