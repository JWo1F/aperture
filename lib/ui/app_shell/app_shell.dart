import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_globals.dart';
import '../../state/connection_views.dart';
import '../../state/session_controller.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../command_palette/command_palette.dart';
import '../connection/master_passphrase_setup.dart';
import '../log/log_panel.dart';
import '../sidebar/sidebar.dart';
import '../widgets/value_selector.dart';
import '../workspace/workspace.dart';
import 'confirm_discard.dart';
import 'connection_lost_banner.dart';
import 'resize_handles.dart';
import 'toast_overlay.dart';
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
      appState.onPassphraseNeeded = () => showMasterPassphraseUnlock(context);
      appState.onConfirmDiscardEdits =
          ({
            required pending,
            required title,
            required action,
            required proceedLabel,
          }) => confirmDiscardEdits(
            context,
            pending: pending,
            title: title,
            action: action,
            proceedLabel: proceedLabel,
          );
    });
  }

  @override
  void didChangeMetrics() {
    // Native window size / position changed — stash the current frame
    // so the next save tick persists it.
    appState.store.captureWindowFrame();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.inactive ||
        lifecycleState == AppLifecycleState.detached) {
      appState.store.captureWindowFrame();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// ⌘W. Goes through the same discard prompt as the tab strip's close
  /// button, so the keystroke can't do quietly what the button asks about.
  void _closeActiveTab() {
    final tabs = appState.tabsController;
    final tab = tabs.activeTab;
    if (tab == null) return;
    unawaited(
      _confirmThen(
        closing: tab,
        close: () => tabs.closeTab(tab.id),
      ),
    );
  }

  Future<void> _confirmThen({
    required WorkspaceTab closing,
    required VoidCallback close,
  }) async {
    final pending = closing is TableTab ? closing.pendingOpCount : 0;
    if (pending > 0) {
      final proceed = await confirmDiscardEdits(
        context,
        pending: pending,
        title: 'Close this tab?',
        action: 'Closing',
        proceedLabel: 'Close anyway',
      );
      if (!proceed) return;
    }
    close();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!HardwareKeyboard.instance.isMetaPressed) return false;
    if (event.logicalKey == LogicalKeyboardKey.bracketLeft) {
      appState.historyBack();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.bracketRight) {
      appState.historyForward();
      return true;
    }
    // ⌘Q is deliberately NOT intercepted: AppKit's terminate reaches
    // `AppLifecycleListener.onExitRequested`, which guards the pending-edit
    // discard for every quit route at once. Handling the keystroke here
    // would leave the app menu and the Dock unguarded.
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Pull only the slices the shell layout reacts to. Sidebar drag,
    // log-panel resize, preference changes, tab mutations etc. all stay
    // out of this widget's rebuild path. The sidebar / log-panel /
    // workspace subtrees subscribe to their own state independently.
    final store = appState.store;
    final eventLog = appState.eventLog;
    final catalog = appState.catalog;
    final tabs = appState.tabsController;
    return Selector<(ConnectionStatus, bool, bool, bool)>(
      listenable: Listenable.merge([
        appState.session,
        store,
        eventLog,
        catalog,
      ]),
      selector: () => (
        appState.session.status,
        store.sidebarVisible,
        eventLog.isVisible,
        catalog.hasSchemas,
      ),
      builder: (context, value) {
        final (status, sidebarVisible, logVisible, _) = value;
        final connected = status == ConnectionStatus.connected;
        final lost = status == ConnectionStatus.lost;
        final showWorkspace = workspaceVisible(appState.session, catalog);

        final body = CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
                showCommandPalette(context),
            const SingleActivator(LogicalKeyboardKey.keyL, meta: true):
                eventLog.toggleVisible,
            // ⌘N and ⌘W are advertised by the tab strip's tooltip, the
            // workspace-home quick actions and the tab context menu, so
            // they have to exist.
            const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
                tabs.newQueryTab,
            const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
                _closeActiveTab,
            if (connected)
              const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () {
                final tab = tabs.activeTab;
                if (tab is TableTab) tabs.refreshTable(tab);
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
                  if (lost) const ConnectionLostBanner(),
                  Expanded(
                    child: Row(
                      children: [
                        // Wrap the sidebar and workspace in RepaintBoundary
                        // so a repaint in one side doesn't dirty the layer
                        // of the other. Cell-edit repaints in the grid no
                        // longer ripple back through the sidebar's
                        // compositor layer, and vice versa.
                        // The welcome screen lists every connection itself,
                        // so the sidebar only accompanies the workspace.
                        if (sidebarVisible && showWorkspace) ...[
                          const RepaintBoundary(child: Sidebar()),
                          const SidebarResizeHandle(),
                        ],
                        Expanded(
                          child: RepaintBoundary(
                            child: Container(
                              color: AppColors.bg,
                              child: showWorkspace
                                  ? const Workspace()
                                  : const WelcomePanel(),
                            ),
                          ),
                        ),
                        if (logVisible) const LogResizeHandle(),
                        const RepaintBoundary(child: LogPanel()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: Stack(
            children: [
              Positioned.fill(child: body),
              const ToastOverlay(),
            ],
          ),
        );
      },
    );
  }
}
