import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/count_format.dart';

/// Live elapsed readout for an in-flight query.
///
/// The wall-clock anchor comes from [startedAt] — `QueryTab.runStartedAt`,
/// set the instant the statement was sent — rather than from a stopwatch
/// this widget owns. Leaving the tab and coming back mid-run therefore
/// resumes the real count instead of restarting from zero.
///
/// Ticking at 10 Hz is cheap only because the rebuild stops here: nothing
/// above this widget listens to the timer, so the toolbar, the editor and
/// the results grid are untouched between ticks.
class RunClock extends StatefulWidget {
  const RunClock({
    super.key,
    required this.startedAt,
    required this.style,
    this.minWidth = 0,
  });

  final DateTime startedAt;
  final TextStyle style;

  /// Reserved width for the digits. The string grows from `0.4s` to
  /// `12.7s` to `1m 04s` during a single run; without a floor the
  /// surrounding row reflows on every carry.
  final double minWidth;

  @override
  State<RunClock> createState() => _RunClockState();
}

class _RunClockState extends State<RunClock> {
  static const _tick = Duration(milliseconds: 100);

  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_tick, (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.startedAt);
    return SizedBox(
      width: widget.minWidth > 0 ? widget.minWidth : null,
      child: Text(
        formatRunElapsed(elapsed),
        textAlign: TextAlign.center,
        style: widget.style,
      ),
    );
  }
}
