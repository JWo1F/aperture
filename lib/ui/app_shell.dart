import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'command_palette/command_palette.dart';
import 'connection/connection_dialog.dart';
import 'connection/connection_menu.dart';
import 'sidebar/sidebar.dart';
import 'widgets/common.dart';
import 'workspace/workspace.dart';

const _windowChannel = MethodChannel('dbv/window');

/// Width reserved on the left of the top toolbar for the macOS traffic-light
/// buttons, which are drawn by the OS on top of our Flutter content.
const double _trafficLightInset = 78;

/// Root layout: toolbar on top, sidebar + workspace in the middle, a thin
/// status bar at the bottom.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final connected = state.status == ConnectionStatus.connected;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
              showCommandPalette(context, state),
        },
        child: FocusScope(
          autofocus: true,
          child: Column(
            children: [
              const _Toolbar(),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: Row(
                  children: [
                    const Sidebar(),
                    const VerticalDivider(width: 1, color: AppColors.border),
                    Expanded(
                      child: Container(
                        color: AppColors.bg,
                        child: connected
                            ? const Workspace()
                            : _WelcomePanel(state: state),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              _StatusBar(state: state),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final connected = state.status == ConnectionStatus.connected;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => _windowChannel.invokeMethod('startDrag'),
      onDoubleTap: () => _windowChannel.invokeMethod('toggleZoom'),
      child: Container(
        height: 48,
        color: AppColors.surface,
        padding: const EdgeInsets.only(
          left: _trafficLightInset,
          right: Insets.md,
        ),
        child: Row(
          children: [
            const Text(
              'DBV',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: _CommandBarTrigger(
                    onTap: () => showCommandPalette(context, state),
                  ),
                ),
              ),
            ),
            const ConnectionMenu(),
            if (connected) ...[
              const SizedBox(width: Insets.sm),
              AppButton(
                label: 'New Query',
                icon: Icons.add,
                onPressed: state.newQueryTab,
              ),
              const SizedBox(width: Insets.sm),
              AppButton(
                label: 'Disconnect',
                icon: Icons.power_settings_new,
                danger: true,
                onPressed: state.disconnect,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Spotlight-style trigger in the center of the toolbar that opens ⌘K.
class _CommandBarTrigger extends StatefulWidget {
  const _CommandBarTrigger({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_CommandBarTrigger> createState() => _CommandBarTriggerState();
}

class _CommandBarTriggerState extends State<_CommandBarTrigger> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hover ? AppColors.surfaceHover : AppColors.bg,
            borderRadius: Radii.brSm,
            border: Border.all(
              color: _hover ? AppColors.borderStrong : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, size: 13, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Search & jump',
                  style: AppTheme.ui(
                    size: 12,
                    color: AppColors.textMuted,
                    weight: FontWeight.w400,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: Radii.brSm,
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  '⌘K',
                  style: AppTheme.mono(size: 10, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown in place of the workspace until a live connection exists.
class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final connecting = state.status == ConnectionStatus.connecting;

    return Container(
      color: AppColors.bg,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(
                  Icons.storage_rounded,
                  size: 28,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: Insets.lg),
              const Text(
                'DBV',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: Insets.sm),
              Text(
                connecting
                    ? 'Establishing connection…'
                    : 'Add a PostgreSQL connection to start browsing.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: Insets.xl),
              if (connecting)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
                )
              else
                AppButton(
                  label: 'New Connection',
                  icon: Icons.add_link,
                  primary: true,
                  onPressed: () => _newConnection(context),
                ),
              if (state.status == ConnectionStatus.error &&
                  state.connectionError != null) ...[
                const SizedBox(height: Insets.xl),
                Container(
                  padding: const EdgeInsets.all(Insets.md),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 15, color: AppColors.error),
                      const SizedBox(width: Insets.sm),
                      Flexible(
                        child: Text(
                          state.connectionError!,
                          style: AppTheme.mono(
                            size: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _newConnection(BuildContext context) async {
    final appState = context.read<AppState>();
    final config = await showConnectionDialog(context);
    if (config == null) return;
    appState.addConnection(config);
    await appState.connect(config);
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final conn = state.activeConnection;
    final connected = state.status == ConnectionStatus.connected;
    final tableCount = state.schemas.fold<int>(
      0,
      (sum, s) => sum + s.tables.length,
    );

    return Container(
      height: 24,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: Insets.md),
      child: Row(
        children: [
          Icon(
            Icons.lan_outlined,
            size: 12,
            color: connected ? AppColors.success : AppColors.textMuted,
          ),
          const SizedBox(width: 6),
          Text(
            connected && conn != null ? conn.summary : 'Disconnected',
            style: AppTheme.mono(size: 10.5, color: AppColors.textMuted),
          ),
          const Spacer(),
          if (connected)
            Text(
              '${state.schemas.length} schemas · $tableCount relations',
              style: AppTheme.mono(size: 10.5, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}
