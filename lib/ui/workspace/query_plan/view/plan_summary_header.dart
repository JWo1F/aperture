import 'package:flutter/material.dart';

import '../../../../theme/app_theme.dart';
import '../model/plan_node.dart';
import 'plan_node_card.dart' show NodeBadge;

/// "execution / planning" headline above the node list, plus the kind
/// badge for the hottest node so the reader sees the headline target
/// before scanning the card stack.
class PlanSummaryHeader extends StatelessWidget {
  const PlanSummaryHeader({
    super.key,
    required this.planningMs,
    required this.executionMs,
    required this.totalNodes,
    required this.slowest,
  });

  final double? planningMs;
  final double? executionMs;
  final int totalNodes;
  final PlanNode slowest;

  @override
  Widget build(BuildContext context) {
    final subtitle = totalNodes == 1
        ? 'Single-node plan'
        : '$totalNodes operations · slowest is ${slowest.kind}';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border.all(color: AppColors.border),
        borderRadius: Radii.brMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (executionMs != null)
                _BigMetric(label: 'execution', valueMs: executionMs!),
              if (executionMs != null) const SizedBox(width: 22),
              if (planningMs != null)
                _BigMetric(
                  label: 'planning',
                  valueMs: planningMs!,
                  muted: true,
                ),
              const Spacer(),
              NodeBadge(type: slowest.kind, small: true),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: AppTheme.mono(size: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _BigMetric extends StatelessWidget {
  const _BigMetric({
    required this.label,
    required this.valueMs,
    this.muted = false,
  });

  final String label;
  final double valueMs;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final primary = muted ? AppColors.textSecondary : AppColors.textPrimary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTheme.mono(
            size: 9.5,
            color: AppColors.textMuted,
            weight: FontWeight.w600,
          ).copyWith(letterSpacing: 0.6),
        ),
        const SizedBox(height: 2),
        RichText(
          text: TextSpan(
            style: AppTheme.mono(
              size: 18,
              color: primary,
              weight: FontWeight.w600,
            ),
            children: [
              TextSpan(text: valueMs.toStringAsFixed(2)),
              TextSpan(
                text: ' ms',
                style: AppTheme.mono(size: 11, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
