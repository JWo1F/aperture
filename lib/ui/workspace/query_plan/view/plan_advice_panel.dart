import 'package:flutter/material.dart';

import '../../../../theme/app_theme.dart';
import '../../../../theme/hugeicons.dart';
import '../model/advice.dart';

/// The stack of advice cards above the node tree. When [items] is empty
/// and the plan wasn't run under ANALYZE, an "estimates only" notice
/// stands in so the user knows why nothing actionable was surfaced.
class PlanAdvicePanel extends StatelessWidget {
  const PlanAdvicePanel({
    super.key,
    required this.items,
    required this.analyzed,
  });

  final List<Advice> items;
  final bool analyzed;

  @override
  Widget build(BuildContext context) {
    final effective = items.isEmpty && !analyzed
        ? [
            Advice(
              severity: AdviceSeverity.info,
              title: 'Plan shown without execution',
              body:
                  'This statement was not run under ANALYZE, so costs are '
                  'estimates and row counts are guesses. Run it as a SELECT '
                  'to see measured times and targeted advice.',
            ),
          ]
        : items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in effective)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _AdviceCard(advice: a),
          ),
      ],
    );
  }
}

class _AdviceCard extends StatelessWidget {
  const _AdviceCard({required this.advice});

  final Advice advice;

  @override
  Widget build(BuildContext context) {
    final color = switch (advice.severity) {
      AdviceSeverity.critical => AppColors.error,
      AdviceSeverity.warn => AppColors.warning,
      AdviceSeverity.info => AppColors.accent,
      AdviceSeverity.good => AppColors.success,
    };
    final icon = switch (advice.severity) {
      AdviceSeverity.critical => Hgi.alertCircle,
      AdviceSeverity.warn => Hgi.alert02,
      AdviceSeverity.info => Hgi.idea01,
      AdviceSeverity.good => Hgi.checkmarkCircle02,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: Radii.brMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  advice.title,
                  style: AppTheme.ui(
                    size: 12,
                    weight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  advice.body,
                  style: AppTheme.mono(
                    size: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
