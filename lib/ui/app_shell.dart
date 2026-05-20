import 'dart:math' as math;

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
        height: 50,
        decoration: BoxDecoration(
          color: AppColors.surface,
          // The faint accent hairline at the bottom edge gives the chrome a
          // sense of "instrument panel" — the workspace below reads as a
          // viewport rather than a continuation of the toolbar.
          border: Border(
            bottom: BorderSide(
              color: AppColors.brightness == AppBrightness.dark
                  ? AppColors.accent.withValues(alpha: 0.08)
                  : AppColors.accent.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
        ),
        padding: const EdgeInsets.only(
          left: _trafficLightInset,
          right: 10,
        ),
        child: Row(
          children: [
            const _BrandMark(),
            const SizedBox(width: 14),
            const ConnectionMenu(),
            const Spacer(),
            _CompactSearch(
              onTap: () => showCommandPalette(context, state),
            ),
            const Spacer(),
            _ActionCluster(
              brightness: state.brightness,
              onToggleTheme: state.toggleBrightness,
              onNewQuery: connected ? state.newQueryTab : null,
              onDisconnect: connected ? state.disconnect : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Hand-drawn aperture iris + lowercase JetBrains Mono wordmark. The mark
/// stands on its own glyph weight — no chip, no rounded background — so the
/// brand reads as "tool" rather than "app icon". The iris is built from four
/// rotated chevrons that converge on a central point, lit in the accent.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CustomPaint(
            painter: _ApertureIrisPainter(
              accent: AppColors.accent,
              dim: AppColors.textMuted,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          'dbv',
          style: AppTheme.mono(
            size: 14,
            color: AppColors.textPrimary,
            weight: FontWeight.w700,
          ).copyWith(letterSpacing: -0.2),
        ),
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

/// Compact search affordance — pill with a tight ⌘K chip and a small magnifier
/// glyph. Sits in the dead-centre of the toolbar but is narrow enough that the
/// header doesn't feel like a search-first interface.
class _CompactSearch extends StatefulWidget {
  const _CompactSearch({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_CompactSearch> createState() => _CompactSearchState();
}

class _CompactSearchState extends State<_CompactSearch> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accentLine = _hover ? AppColors.accent : AppColors.borderStrong;

    return Tooltip(
      message: 'Search & jump  ⌘K',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            height: 28,
            padding: const EdgeInsets.only(left: 11, right: 5),
            decoration: BoxDecoration(
              color: _hover ? AppColors.surfaceHover : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accentLine),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search,
                  size: 12,
                  color: _hover ? AppColors.accent : AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  'jump…',
                  style: AppTheme.mono(
                    size: 11,
                    color: AppColors.textSecondary,
                    weight: FontWeight.w400,
                  ),
                ),
                const SizedBox(width: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '⌘K',
                    style: AppTheme.mono(
                      size: 9.5,
                      color: AppColors.textSecondary,
                      weight: FontWeight.w600,
                    ).copyWith(letterSpacing: 0.4),
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

/// Right-side action group — one rounded shell with hairline rails between
/// the cells. Reads as a single transport panel rather than a row of
/// disconnected pills, which is the standard SaaS-dashboard tell.
class _ActionCluster extends StatelessWidget {
  const _ActionCluster({
    required this.brightness,
    required this.onToggleTheme,
    required this.onNewQuery,
    required this.onDisconnect,
  });

  final AppBrightness brightness;
  final VoidCallback onToggleTheme;
  final VoidCallback? onNewQuery;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final connected = onNewQuery != null;
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ClusterCell(
            onTap: onToggleTheme,
            tooltip: brightness == AppBrightness.dark
                ? 'Switch to light theme'
                : 'Switch to dark theme',
            child: _ThemeCellGlyph(brightness: brightness),
          ),
          if (connected) ...[
            _ClusterDivider(),
            _ClusterCell(
              accent: true,
              onTap: onNewQuery,
              tooltip: 'New query  ⌘N',
              horizontalPad: 12,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 13, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text(
                    'Query',
                    style: AppTheme.ui(
                      size: 12,
                      color: AppColors.accent,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            _ClusterDivider(),
            _ClusterCell(
              hoverFg: AppColors.error,
              onTap: onDisconnect,
              tooltip: 'Disconnect',
              child: Icon(
                Icons.power_settings_new,
                size: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One pressable cell inside [_ActionCluster]. Hover paints the cell, not
/// the icon's own background, so the shell stays the visual unit.
class _ClusterCell extends StatefulWidget {
  const _ClusterCell({
    required this.child,
    required this.onTap,
    this.tooltip,
    this.horizontalPad = 8,
    this.accent = false,
    this.hoverFg,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;
  final double horizontalPad;
  final bool accent;
  final Color? hoverFg;

  @override
  State<_ClusterCell> createState() => _ClusterCellState();
}

class _ClusterCellState extends State<_ClusterCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final Color hoverBg = widget.accent
        ? AppColors.accentSoft
        : AppColors.surfaceHover;

    Widget child = widget.child;
    // Replace child's foreground color on hover by re-wrapping iconography.
    if (_hover && widget.hoverFg != null && widget.child is Icon) {
      final i = widget.child as Icon;
      child = Icon(i.icon, size: i.size, color: widget.hoverFg);
    }

    final cell = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 28,
          padding: EdgeInsets.symmetric(horizontal: widget.horizontalPad),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover && enabled ? hoverBg : Colors.transparent,
          ),
          child: child,
        ),
      ),
    );

    if (widget.tooltip == null) return cell;
    return Tooltip(message: widget.tooltip!, child: cell);
  }
}

/// 1px vertical hairline used between [_ClusterCell]s.
class _ClusterDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 28, color: AppColors.border);
  }
}

/// Sun ⇄ moon glyph inside an action cluster cell. Fade-rotates between the
/// two states on toggle.
class _ThemeCellGlyph extends StatelessWidget {
  const _ThemeCellGlyph({required this.brightness});
  final AppBrightness brightness;

  @override
  Widget build(BuildContext context) {
    final isDark = brightness == AppBrightness.dark;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, anim) {
        return FadeTransition(
          opacity: anim,
          child: RotationTransition(
            turns: Tween<double>(begin: 0.55, end: 1).animate(anim),
            child: child,
          ),
        );
      },
      child: Icon(
        isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
        key: ValueKey(isDark),
        size: 14,
        color: AppColors.textSecondary,
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
