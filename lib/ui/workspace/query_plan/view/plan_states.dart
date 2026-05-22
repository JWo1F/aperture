import 'package:flutter/material.dart';

import '../../../../theme/app_theme.dart';
import '../../../widgets/common.dart';

class PlanSpinner extends StatelessWidget {
  const PlanSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 1.6,
          color: AppColors.accent,
        ),
      ),
    );
  }
}

class PlanSuggestion extends StatelessWidget {
  const PlanSuggestion({super.key, required this.enabled, required this.onRun});

  final bool enabled;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 30,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 10),
            Text(
              'See how Postgres runs your query',
              style: AppTheme.ui(
                size: 13.5,
                weight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              enabled
                  ? 'EXPLAIN walks every step of the plan: which tables it '
                        'reads, how it joins them, and where time is spent.'
                  : 'Run a query first — the plan explains your most recent '
                        'run, the same SQL the Results tab shows.',
              textAlign: TextAlign.center,
              style: AppTheme.mono(size: 11.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            AppButton(
              label: 'Run EXPLAIN',
              icon: Icons.account_tree_outlined,
              primary: true,
              onPressed: onRun,
            ),
          ],
        ),
      ),
    );
  }
}

class PlanError extends StatelessWidget {
  const PlanError({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 14, color: AppColors.error),
              const SizedBox(width: 6),
              Text(
                'EXPLAIN failed',
                style: AppTheme.ui(
                  size: 12,
                  weight: FontWeight.w600,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            message,
            style: AppTheme.mono(size: 11.5, color: AppColors.textSecondary),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            AppButton(
              label: 'Run again',
              icon: Icons.refresh,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}

class PlanStaleBanner extends StatelessWidget {
  const PlanStaleBanner({super.key, required this.onRerun});

  final VoidCallback onRerun;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: Radii.brMd,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_outlined,
            size: 12,
            color: AppColors.warning,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Plan is for an earlier run.',
              style: AppTheme.mono(size: 11, color: AppColors.warning),
            ),
          ),
          AppButton(
            label: 'Re-run EXPLAIN',
            icon: Icons.refresh,
            onPressed: onRerun,
          ),
        ],
      ),
    );
  }
}
