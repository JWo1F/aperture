import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/connection_config.dart';
import '../../models/time_ago.dart';
import '../../state/app_state.dart';
import '../../state/connection_registry.dart';
import '../../state/session_controller.dart';
import '../../theme/app_theme.dart';
import '../about/about_dialog.dart';
import '../connection/connection_dialog.dart';
import '../widgets/common.dart';

/// Shown in place of the workspace until a live connection exists. Surfaces
/// the most recently used connections as quick-launch cards.
class WelcomePanel extends StatelessWidget {
  const WelcomePanel({super.key});

  Future<void> _newConnection(BuildContext context) async {
    final appState = context.read<AppState>();
    final registry = context.read<ConnectionRegistry>();
    final config = await showConnectionDialog(context);
    if (config == null) return;
    registry.add(config);
    await appState.connect(config);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final session = context.read<SessionController>();
    final registry = context.read<ConnectionRegistry>();
    final connecting = session.status == ConnectionStatus.connecting;
    final recents = registry.recent;
    final hasAny = registry.all.isNotEmpty;

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
                    onConnect: appState.connect,
                    onNew: () => _newConnection(context),
                  )
                else
                  _EmptyBlock(
                    hasAny: hasAny,
                    onNew: () => _newConnection(context),
                  ),
                if (session.status == ConnectionStatus.error &&
                    session.error != null) ...[
                  const SizedBox(height: Insets.xl),
                  _ErrorBox(message: session.error!),
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
    final appState = context.read<AppState>();
    final updated = await showConnectionDialog(context, existing: config);
    if (updated != null) appState.updateConnection(updated);
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

/// Hex-framed iris glyph for the welcome screen's brand hero — three
/// shutter blades converging on the centre, drawn cheaply enough to stay
/// readable at small sizes.
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
