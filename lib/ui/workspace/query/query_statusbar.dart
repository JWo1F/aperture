import 'package:flutter/material.dart';

import '../../../models/count_format.dart';
import '../../../state/workspace_tab.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/pagebar.dart';
import 'run_clock.dart';

/// Bottom strip of the query page — the run's numbers, in the same chrome
/// the table view uses for its pagebar.
///
/// While a statement is in flight the whole strip switches to live state
/// rather than leaving the previous run's figures on screen: reading
/// "1,204 rows · 12ms" under a spinning Run button is worse than reading
/// nothing, because it looks like the answer.
class QueryStatusBar extends StatelessWidget {
  const QueryStatusBar({
    super.key,
    required this.tab,
    required this.runningIndex,
    required this.statementCount,
  });

  final QueryTab tab;

  /// 1-based position of the in-flight statement within the script, when it
  /// could be resolved — the Run-all loop's progress readout.
  final int? runningIndex;
  final int statementCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: pagebarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: tab.running ? _buildRunning() : _buildIdle(),
    );
  }

  Widget _buildRunning() {
    final startedAt = tab.runStartedAt;
    final stopping = tab.cancelRequested;
    final tint = stopping ? AppColors.warn : AppColors.accent;
    return Row(
      children: [
        _PulseDot(color: tint),
        const SizedBox(width: 7),
        Text(
          stopping ? 'cancelling' : 'running',
          style: AppTheme.mono(size: 10.5, color: tint, weight: FontWeight.w600),
        ),
        if (startedAt != null) ...[
          const PbDot(),
          RunClock(
            startedAt: startedAt,
            style: AppTheme.mono(
              size: 10.5,
              color: AppColors.textPrimary,
              weight: FontWeight.w600,
            ),
          ),
        ],
        if (runningIndex != null && statementCount > 1) ...[
          const PbDot(),
          PbStat(
            head: 'statement ',
            mid: '$runningIndex',
            tail: ' of $statementCount',
          ),
        ],
      ],
    );
  }

  Widget _buildIdle() {
    final result = tab.result;
    final refreshedAt = tab.lastRefreshedAt;
    return Row(
      children: [
        if (result == null)
          const PbStat(head: 'idle')
        else ...[
          if (result.hasColumns)
            PbStat(
              head: withCommas(result.rows.length),
              tail: ' rows',
              headHighlight: true,
            )
          else if (result.affectedRows != null)
            PbStat(
              head: withCommas(result.affectedRows!),
              tail: ' affected',
              headHighlight: true,
            )
          else
            const PbStat(head: 'done'),
          const PbDot(),
          PbStat(head: '${result.elapsed.inMilliseconds}', tail: 'ms'),
          if (result.truncatedAt != null) ...[
            const PbDot(),
            PbStat(head: 'truncated at ', mid: withCommas(result.truncatedAt!)),
          ],
        ],
        if (refreshedAt != null) ...[
          const PbDot(),
          PbStat(head: 'refreshed ', mid: formatPagebarClock(refreshedAt)),
        ],
        const Spacer(),
        if (result != null) _Outcome(error: result.isError),
      ],
    );
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome({required this.error});

  final bool error;

  @override
  Widget build(BuildContext context) {
    final tint = error ? AppColors.error : AppColors.success;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          error ? 'error' : 'success',
          style: AppTheme.mono(size: 10.5, color: tint),
        ),
      ],
    );
  }
}

/// Breathing indicator for the in-flight state. Rebuilds only itself, so
/// the animation costs nothing outside these six pixels.
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});

  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.35 + 0.65 * _pulse.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
