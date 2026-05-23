import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/connection_config.dart';
import '../../../models/time_ago.dart';
import '../../../theme/app_theme.dart';

class HomeHero extends StatelessWidget {
  const HomeHero({
    super.key,
    required this.connection,
    required this.tint,
    required this.serverVersion,
  });

  final ConnectionConfig? connection;
  final Color tint;
  final String? serverVersion;

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Working late';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    if (h < 22) return 'Good evening';
    return 'Working late';
  }

  @override
  Widget build(BuildContext context) {
    final name = connection?.name ?? 'Database';
    final summary = connection?.summary ?? '';
    final engineLabel = connection?.engine == DbEngine.sqlite
        ? 'SQLite'
        : 'PostgreSQL';
    final connectedAt = connection?.lastConnectedAt;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 60,
          height: 60,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: Radii.brMd,
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: tint.withValues(alpha: 0.18),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: _AnimatedIris(tint: tint),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting().toUpperCase(),
                style: AppTheme.eyebrow(color: tint),
              ),
              const SizedBox(height: 5),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.ui(
                  size: 23,
                  weight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 8),
              if (summary.isNotEmpty)
                Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono(
                    size: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        _StatusColumn(
          tint: tint,
          engineLabel: engineLabel,
          serverVersion: serverVersion,
          connectedAt: connectedAt,
        ),
      ],
    );
  }
}

/// Right-hand side of the hero: a live "connected" pill plus engine/version
/// metadata, right-aligned so it reads as a status block.
class _StatusColumn extends StatelessWidget {
  const _StatusColumn({
    required this.tint,
    required this.engineLabel,
    required this.serverVersion,
    required this.connectedAt,
  });

  final Color tint;
  final String engineLabel;
  final String? serverVersion;
  final DateTime? connectedAt;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LiveDot(color: AppColors.success),
            const SizedBox(width: 6),
            Text(
              'Connected',
              style: AppTheme.ui(
                size: 11.5,
                weight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            _MetaChip(label: engineLabel, tint: tint),
            if (serverVersion != null && serverVersion!.isNotEmpty)
              _MetaChip(label: serverVersion!, tint: tint),
          ],
        ),
        if (connectedAt != null) ...[
          const SizedBox(height: 8),
          Text(
            'session ${timeAgo(connectedAt!)}',
            style: AppTheme.mono(size: 10, color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.tint});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: Radii.brSm,
        border: Border.all(color: tint.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: AppTheme.mono(size: 10, color: AppColors.textSecondary),
      ),
    );
  }
}

/// A tiny pulsing dot — signals the connection is live.
class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.color});

  final Color color;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 8,
      height: 8,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.22 * (1 - _c.value)),
                ),
              ),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AnimatedIris extends StatefulWidget {
  const _AnimatedIris({required this.tint});

  final Color tint;

  @override
  State<_AnimatedIris> createState() => _AnimatedIrisState();
}

class _AnimatedIrisState extends State<_AnimatedIris>
    with SingleTickerProviderStateMixin {
  // Plays a single 5-second intro flourish — one full rotation and two
  // aperture breaths — then eases to a stop on a closed, home-rotation iris.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => CustomPaint(
          painter: _IrisPainter(
            t: Curves.easeOutCubic.transform(_c.value),
            tint: widget.tint,
            dim: AppColors.borderStrong,
          ),
        ),
      ),
    );
  }
}

/// Six shutter blades that rotate slowly while the aperture opening breathes
/// open and shut — a living version of the welcome-screen brand glyph.
class _IrisPainter extends CustomPainter {
  _IrisPainter({required this.t, required this.tint, required this.dim});

  final double t;
  final Color tint;
  final Color dim;

  static const int _blades = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);
    final r = size.width / 2 - 1;

    // One full slow rotation per loop; the aperture breathes twice as fast.
    final rot = t * 2 * math.pi;
    final breathe = 0.5 - 0.5 * math.cos(t * 4 * math.pi);
    final aperture = r * (0.16 + 0.30 * breathe);

    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = dim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..isAntiAlias = true,
    );

    final bladeFill = Paint()
      ..color = tint.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final edge = Paint()
      ..color = tint.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final step = 2 * math.pi / _blades;
    for (var i = 0; i < _blades; i++) {
      final a0 = rot + i * step;
      final a1 = a0 + step;
      final outerA = Offset(cx + r * math.cos(a0), cy + r * math.sin(a0));
      final outerB = Offset(cx + r * math.cos(a1), cy + r * math.sin(a1));
      // Leading inner vertex — sits on the aperture circle, twisted off the
      // outer vertex so the blades overlap like a real iris.
      final inner = Offset(
        cx + aperture * math.cos(a1 + 0.55),
        cy + aperture * math.sin(a1 + 0.55),
      );
      final blade = Path()
        ..moveTo(outerA.dx, outerA.dy)
        ..lineTo(outerB.dx, outerB.dy)
        ..lineTo(inner.dx, inner.dy)
        ..close();
      canvas.drawPath(blade, bladeFill);
      canvas.drawLine(outerA, inner, edge);
    }

    // Centre point — pulses with the aperture.
    canvas.drawCircle(
      center,
      1.4 + breathe * 1.6,
      Paint()
        ..color = tint
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_IrisPainter old) =>
      old.t != t || old.tint != tint || old.dim != dim;
}
