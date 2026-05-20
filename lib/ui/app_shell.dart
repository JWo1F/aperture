import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/connection_config.dart';
import '../models/time_ago.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'command_palette/command_palette.dart';
import 'connection/connection_dialog.dart';
import 'connection/connection_menu.dart';
import 'sidebar/sidebar.dart';
import 'widgets/common.dart';
import 'widgets/table_glyph.dart';
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

class _AppShellState extends State<AppShell> {
  @override
  void initState() {
    super.initState();
    // ⌘[ / ⌘] are intercepted at the HardwareKeyboard layer so they fire
    // regardless of focus — a TextField inside the active tab would
    // otherwise swallow them via Flutter's default editing shortcuts.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
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
    return false;
  }

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
          if (connected)
            const SingleActivator(LogicalKeyboardKey.keyR, meta: true):
                () => state.refreshCatalog(),
        },
        child: FocusScope(
          autofocus: true,
          child: Column(
            children: [
              const RepaintBoundary(child: _Toolbar()),
              Divider(height: 1, color: AppColors.border),
              Expanded(
                child: Row(
                  children: [
                    // Wrap the sidebar and workspace in RepaintBoundary so a
                    // repaint in one side doesn't dirty the layer of the
                    // other. Cell-edit repaints in the grid no longer ripple
                    // back through the sidebar's compositor layer, and vice
                    // versa.
                    const RepaintBoundary(child: Sidebar()),
                    VerticalDivider(width: 1, color: AppColors.border),
                    Expanded(
                      child: RepaintBoundary(
                        child: Container(
                          color: AppColors.bg,
                          child: connected
                              ? const Workspace()
                              : _WelcomePanel(state: state),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.border),
              RepaintBoundary(child: _StatusBar(state: state)),
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
        height: 52,
        color: AppColors.surface,
        padding: const EdgeInsets.only(
          left: _trafficLightInset,
          right: Insets.md,
        ),
        child: Row(
          children: [
            const _BrandMark(),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _CommandBarTrigger(
                    onTap: () => showCommandPalette(context, state),
                  ),
                ),
              ),
            ),
            const ConnectionMenu(),
            const SizedBox(width: 10),
            const Rail(height: 20),
            const SizedBox(width: 2),
            _ThemeToggle(
              brightness: state.brightness,
              onTap: state.toggleBrightness,
            ),
            if (connected) ...[
              const SizedBox(width: 2),
              const Rail(height: 20),
              const SizedBox(width: 10),
              AppButton(
                label: 'New Query',
                icon: Icons.add,
                primary: true,
                onPressed: state.newQueryTab,
              ),
              const SizedBox(width: Insets.sm),
              IconAction(
                icon: Icons.power_settings_new,
                tooltip: 'Disconnect',
                onPressed: state.disconnect,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Wordmark + small table glyph in the accent. The glyph carries the
/// "this app is about tables" semantic without resorting to a stock icon,
/// and the indigo tint keeps it tied to the rest of the chrome.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: Radii.brSm,
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.32)),
          ),
          child: TableGlyph(size: 11, color: AppColors.accent),
        ),
        const SizedBox(width: 10),
        Text(
          'DBV',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(width: 8),
        Container(width: 3, height: 3, decoration: BoxDecoration(
          color: AppColors.textMuted,
          shape: BoxShape.circle,
        )),
        const SizedBox(width: 8),
        Text(
          'postgres',
          style: AppTheme.ui(
            size: 10.5,
            color: AppColors.textMuted,
            weight: FontWeight.w500,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

/// Spotlight-style trigger in the center of the toolbar that opens ⌘K.
/// The bottom edge lights up in the accent on hover — a single quiet signal
/// that this thing is the search bar without resorting to a focus ring.
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
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: _hover ? AppColors.surfaceHover : AppColors.bg,
            borderRadius: Radii.brSm,
            border: Border.all(
              color: _hover ? AppColors.accent : AppColors.border,
            ),
            boxShadow: _hover
                ? [
                    BoxShadow(
                      color: AppColors.accentSoft,
                      blurRadius: 10,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                Icons.search,
                size: 13,
                color: _hover ? AppColors.accent : AppColors.textSecondary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Search tables, queries, schemas',
                  style: AppTheme.ui(
                    size: 12,
                    color: AppColors.textMuted,
                    weight: FontWeight.w400,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: Radii.brSm,
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  '⌘K',
                  style: AppTheme.mono(
                    size: 10,
                    color: AppColors.textSecondary,
                    weight: FontWeight.w500,
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

/// Sun / moon toggle that swaps [AppColors] between the dark and light
/// palettes. Icon morphs with a quick rotate-fade rather than a hard swap.
class _ThemeToggle extends StatefulWidget {
  const _ThemeToggle({required this.brightness, required this.onTap});

  final AppBrightness brightness;
  final VoidCallback onTap;

  @override
  State<_ThemeToggle> createState() => _ThemeToggleState();
}

class _ThemeToggleState extends State<_ThemeToggle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.brightness == AppBrightness.dark;
    final icon = isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined;
    final tooltip = isDark ? 'Switch to light theme' : 'Switch to dark theme';

    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? AppColors.surfaceHover : Colors.transparent,
              borderRadius: Radii.brSm,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) {
                return FadeTransition(
                  opacity: anim,
                  child: RotationTransition(
                    turns: Tween<double>(begin: 0.6, end: 1).animate(anim),
                    child: child,
                  ),
                );
              },
              child: Icon(
                icon,
                key: ValueKey(isDark),
                size: 16,
                color: _hover ? AppColors.accent : AppColors.textSecondary,
              ),
            ),
          ),
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
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: Radii.brMd,
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(
            Icons.storage_rounded,
            size: 24,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'DBV',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
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
              _RecentCard(config: c, onTap: () => onConnect(c)),
          ],
        ),
        const SizedBox(height: 18),
        _NewConnectionLink(onTap: onNew),
      ],
    );
  }
}

class _RecentCard extends StatefulWidget {
  const _RecentCard({required this.config, required this.onTap});
  final ConnectionConfig config;
  final VoidCallback onTap;

  @override
  State<_RecentCard> createState() => _RecentCardState();
}

class _RecentCardState extends State<_RecentCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final ts = config.lastConnectedAt;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 260,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _hover ? AppColors.surfaceHover : AppColors.surface,
            borderRadius: Radii.brMd,
            border: Border.all(
              color: _hover ? AppColors.accent : AppColors.border,
            ),
            boxShadow: _hover
                ? const [
                    BoxShadow(
                      color: Color(0x335B7CFA),
                      blurRadius: 16,
                      offset: Offset(0, 4),
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
                      color: AppColors.accent,
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
                  if (ts != null)
                    Text(
                      timeAgo(ts),
                      style: AppTheme.mono(
                        size: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                config.summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.mono(
                  size: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewConnectionLink extends StatefulWidget {
  const _NewConnectionLink({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_NewConnectionLink> createState() => _NewConnectionLinkState();
}

class _NewConnectionLinkState extends State<_NewConnectionLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add,
              size: 13,
              color: _hover ? AppColors.accentHover : AppColors.accent,
            ),
            const SizedBox(width: 6),
            Text(
              'New connection',
              style: AppTheme.ui(
                size: 12,
                color: _hover ? AppColors.accentHover : AppColors.accent,
                weight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
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
            Icon(Icons.error_outline,
                size: 15, color: AppColors.error),
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
