import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import '../../widgets/common.dart';
import 'run_clock.dart';

/// The query page's primary execute control, and the one place the page
/// reports that something is happening.
///
/// It is a single button through all three phases rather than a Run that
/// disables next to a Stop that appears: the control the user pressed is
/// the control they press again to take it back, and the elapsed counter
/// rides inside it so the answer to "is this hung?" is where the eye
/// already is.
///
/// Phases: idle (accent fill, ▶ Run, ⌘↵), running (error fill, a sweeping
/// ring around a stop square, live counter), stopping (the same, dimmed
/// and inert, until the driver acknowledges the cancel).
class RunButton extends StatefulWidget {
  const RunButton({
    super.key,
    required this.running,
    required this.cancelRequested,
    required this.startedAt,
    required this.onRun,
    required this.onStop,
  });

  final bool running;
  final bool cancelRequested;

  /// Wall-clock start of the in-flight statement; null when idle.
  final DateTime? startedAt;

  /// Null disables the idle phase — nothing to run, or a run is already
  /// in flight.
  final VoidCallback? onRun;
  final VoidCallback? onStop;

  @override
  State<RunButton> createState() => _RunButtonState();
}

class _RunButtonState extends State<RunButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _syncSweep();
  }

  @override
  void didUpdateWidget(RunButton old) {
    super.didUpdateWidget(old);
    _syncSweep();
  }

  /// The ring spins only while the statement is genuinely in flight — once
  /// a cancel is requested the motion stops, which is the whole signal
  /// that the request landed.
  void _syncSweep() {
    final spinning = widget.running && !widget.cancelRequested;
    if (spinning && !_sweep.isAnimating) {
      _sweep.repeat();
    } else if (!spinning && _sweep.isAnimating) {
      _sweep.stop();
      _sweep.value = 0;
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Each phase has its own intrinsic width — `Run ⌘↵` is narrower than
    // `Stop 4.2s`, which is narrower than `Stopping…`. Easing the box
    // instead of snapping it keeps the buttons to the right of this one
    // from twitching every time a run starts or is called off.
    return AnimatedSize(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerLeft,
      child: widget.running ? _buildRunning() : _buildIdle(),
    );
  }

  Widget _buildIdle() {
    final enabled = widget.onRun != null;
    return Hoverable(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onTap: widget.onRun,
      builder: (context, hovering) => _Shell(
        fill: enabled
            ? (hovering ? AppColors.accentHover : AppColors.accent)
            : AppColors.accent.withValues(alpha: 0.4),
        children: [
          const Icon(Hgi.play, size: 12, color: Colors.white),
          const SizedBox(width: 6),
          const _Label('Run'),
          const SizedBox(width: 8),
          const KbdCluster(['⌘', '↵'], size: 9.5, onAccent: true),
        ],
      ),
    );
  }

  Widget _buildRunning() {
    final stopping = widget.cancelRequested;
    final base = AppColors.error;
    return Hoverable(
      cursor: stopping ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onTap: stopping ? null : widget.onStop,
      builder: (context, hovering) => _Shell(
        fill: stopping
            ? base.withValues(alpha: 0.5)
            : (hovering ? Color.lerp(base, Colors.white, 0.14)! : base),
        children: [
          _SweepingStop(progress: _sweep, dimmed: stopping),
          const SizedBox(width: 7),
          _Label(stopping ? 'Stopping…' : 'Stop'),
          const SizedBox(width: 8),
          _ClockChip(startedAt: widget.startedAt),
        ],
      ),
    );
  }
}

/// Shared chassis for both phases. Reusing one `AnimatedContainer` across
/// the idle/running swap is what makes the fill cross-fade from accent to
/// error rather than cutting.
class _Shell extends StatelessWidget {
  const _Shell({required this.fill, required this.children});

  final Color fill;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: 24,
      padding: const EdgeInsets.only(left: 9, right: 6),
      decoration: BoxDecoration(color: fill, borderRadius: Radii.brSm),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTheme.ui(
        size: 11.5,
        color: Colors.white,
        weight: FontWeight.w600,
      ),
    );
  }
}

/// The counter sits in the same translucent chip the ⌘↵ hint occupies when
/// idle, so the two phases read as one control changing its mind rather
/// than two buttons trading places.
class _ClockChip extends StatelessWidget {
  const _ClockChip({required this.startedAt});

  final DateTime? startedAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 15,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: Radii.brSm,
      ),
      child: startedAt == null
          ? const SizedBox(width: 38)
          : RunClock(
              startedAt: startedAt!,
              minWidth: 38,
              style: AppTheme.mono(
                size: 9.5,
                color: Colors.white.withValues(alpha: 0.95),
                weight: FontWeight.w600,
              ).copyWith(height: 1.0),
            ),
    );
  }
}

/// A stop square inside a ring whose lit arc sweeps around it. The square
/// is the affordance, the arc is the liveness — together they say "working,
/// click to take it back" in 14 pixels.
class _SweepingStop extends StatelessWidget {
  const _SweepingStop({required this.progress, required this.dimmed});

  final Animation<double> progress;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: AnimatedBuilder(
        animation: progress,
        builder: (context, _) => CustomPaint(
          painter: _SweepPainter(
            turn: progress.value,
            opacity: dimmed ? 0.5 : 1,
          ),
        ),
      ),
    );
  }
}

class _SweepPainter extends CustomPainter {
  _SweepPainter({required this.turn, required this.opacity});

  final double turn;
  final double opacity;

  static const _arcSweep = math.pi * 0.55;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final ring = rect.deflate(0.7);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withValues(alpha: 0.28 * opacity);
    canvas.drawArc(ring, 0, math.pi * 2, false, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.95 * opacity);
    canvas.drawArc(
      ring,
      turn * math.pi * 2 - math.pi / 2,
      _arcSweep,
      false,
      arc,
    );

    final square = Paint()
      ..color = Colors.white.withValues(alpha: 0.95 * opacity);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: rect.center,
          width: 4.6,
          height: 4.6,
        ),
        const Radius.circular(1),
      ),
      square,
    );
  }

  @override
  bool shouldRepaint(_SweepPainter old) =>
      old.turn != turn || old.opacity != opacity;
}
