import 'package:flutter/material.dart';

import '../../../models/count_format.dart';
import '../../../state/workspace_tab.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import '../../widgets/common.dart';

/// Section selector between the editor and the results pane.
///
/// Counts live on the tabs themselves rather than only in the status bar,
/// so a run that produced rows and a run that produced three notices are
/// distinguishable without switching sections first.
class ResultsTabStrip extends StatelessWidget {
  const ResultsTabStrip({super.key, required this.tab});

  final QueryTab tab;

  @override
  Widget build(BuildContext context) {
    final result = tab.result;
    final rowCount = result != null && result.hasColumns
        ? result.rows.length
        : null;
    final messageCount = tab.messages.length;

    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 6),
          _SectionTab(
            icon: Hgi.table,
            label: 'Results',
            badge: rowCount == null ? null : compactCount(rowCount),
            active: tab.view == QueryResultsView.results,
            onTap: () => tab.setView(QueryResultsView.results),
          ),
          _SectionTab(
            icon: Hgi.hierarchy,
            label: 'Plan',
            active: tab.view == QueryResultsView.plan,
            onTap: () => tab.setView(QueryResultsView.plan),
          ),
          _SectionTab(
            icon: Hgi.message01,
            label: 'Messages',
            badge: messageCount == 0 ? null : compactCount(messageCount),
            active: tab.view == QueryResultsView.messages,
            onTap: () => tab.setView(QueryResultsView.messages),
          ),
        ],
      ),
    );
  }
}

class _SectionTab extends StatelessWidget {
  const _SectionTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) {
        final fg = active
            ? AppColors.textPrimary
            : (hovering ? AppColors.textSecondary : AppColors.textMuted);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active
                ? AppColors.accentSoft
                : (hovering
                      ? AppColors.surfaceHover
                      : AppColors.surfaceHover.withValues(alpha: 0)),
            // The rule reads as the section's own edge rather than a
            // floating marker, so it hugs the strip's hairline.
            border: Border(
              bottom: BorderSide(
                color: active ? AppColors.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: fg),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: AppTheme.mono(
                  size: 10,
                  color: fg,
                  weight: FontWeight.w600,
                ).copyWith(letterSpacing: 0.06 * 10),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Text(
                  badge!,
                  style: AppTheme.mono(
                    size: 9.5,
                    color: active ? AppColors.accent : AppColors.text4,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
