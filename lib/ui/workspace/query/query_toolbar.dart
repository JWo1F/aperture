import 'package:flutter/material.dart';

import '../../../state/workspace_tab.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import '../../widgets/common.dart';
import 'run_button.dart';

/// Header of the query page. Three zones, left to right: the execute
/// cluster, the caret readout, and the destructive action kept out on its
/// own at the far edge.
///
/// Manual and automatic refresh deliberately live in the app-shell toolbar
/// for query tabs — repeating them here would give the same run two
/// buttons in two chromes a few pixels apart.
class QueryToolbar extends StatelessWidget {
  const QueryToolbar({
    super.key,
    required this.tab,
    required this.statementIndex,
    required this.statementCount,
    required this.statementKindLabel,
    required this.onRunStatement,
    required this.onRunAll,
    required this.onStop,
    required this.onExplain,
  });

  final QueryTab tab;

  /// 1-based index of the statement under the caret, or null when the caret
  /// sits between statements.
  final int? statementIndex;
  final int statementCount;
  final String? statementKindLabel;

  final VoidCallback? onRunStatement;
  final VoidCallback? onRunAll;
  final VoidCallback onStop;
  final VoidCallback? onExplain;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          RunButton(
            running: tab.running,
            cancelRequested: tab.cancelRequested,
            startedAt: tab.runStartedAt,
            onRun: onRunStatement,
            onStop: onStop,
          ),
          const SizedBox(width: 5),
          GhostButton(
            label: 'Run all',
            icon: Hgi.flash,
            kbd: const ['⌘', '⇧', '↵'],
            onPressed: onRunAll,
          ),
          const Rail(height: 16),
          GhostButton(
            label: 'Explain',
            icon: Hgi.hierarchy,
            busy: tab.planLoading,
            onPressed: onExplain,
          ),
          // Clipped rather than shrunk: at a window narrow enough to squeeze
          // this readout, losing it is better than scaling the toolbar's
          // only free-width element down to illegibility.
          Expanded(
            child: ClipRect(
              child: Center(
                child: _StatementContext(
                  index: statementIndex,
                  count: statementCount,
                  kind: statementKindLabel,
                ),
              ),
            ),
          ),
          IconAction(
            icon: Hgi.eraser,
            tooltip: 'Clear results',
            onPressed: tab.result == null ? null : tab.clearResult,
          ),
        ],
      ),
    );
  }
}

/// Quiet outline button sized to sit level with [RunButton]. The border
/// only materialises on hover so a row of them reads as one calm cluster
/// at rest.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.kbd,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final List<String>? kbd;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Hoverable(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onTap: enabled ? onPressed : null,
      builder: (context, hovering) {
        final active = hovering && enabled;
        final fg = enabled
            ? (active ? AppColors.textPrimary : AppColors.textSecondary)
            : AppColors.textMuted.withValues(alpha: 0.5);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: 24,
          padding: EdgeInsets.only(left: 9, right: kbd == null ? 9 : 6),
          decoration: BoxDecoration(
            color: active
                ? AppColors.surfaceHover
                : AppColors.surfaceHover.withValues(alpha: 0),
            borderRadius: Radii.brSm,
            border: Border.all(
              color: active ? AppColors.borderStrong : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppColors.accent,
                  ),
                )
              else
                Icon(icon, size: 12, color: fg),
              const SizedBox(width: 5),
              Text(
                label,
                style: AppTheme.ui(
                  size: 11.5,
                  color: fg,
                  weight: FontWeight.w500,
                ),
              ),
              if (kbd != null) ...[
                const SizedBox(width: 7),
                KbdCluster(kbd!, size: 10),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// What ⌘↵ is about to send, stated before it is sent.
///
/// A script's statements are indistinguishable at a glance once it passes
/// a screenful, and Run-statement picks by caret position — this is the
/// only thing standing between "run the SELECT I'm looking at" and running
/// the DELETE two blocks up.
class _StatementContext extends StatelessWidget {
  const _StatementContext({
    required this.index,
    required this.count,
    required this.kind,
  });

  final int? index;
  final int count;
  final String? kind;

  @override
  Widget build(BuildContext context) {
    if (count == 0) {
      return Text(
        'no statement',
        style: AppTheme.mono(size: 10.5, color: AppColors.text4),
      );
    }
    if (index == null) {
      return Text(
        count == 1 ? '1 statement' : '$count statements',
        style: AppTheme.mono(size: 10.5, color: AppColors.text4),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (count > 1) ...[
          Text(
            '$index/$count',
            style: AppTheme.mono(size: 10.5, color: AppColors.text4),
          ),
          Text(
            '  ·  ',
            style: AppTheme.mono(size: 10.5, color: AppColors.text4),
          ),
        ],
        Text(
          kind ?? '—',
          style: AppTheme.mono(
            size: 10.5,
            color: AppColors.textSecondary,
            weight: FontWeight.w600,
          ).copyWith(letterSpacing: 0.05 * 10.5),
        ),
      ],
    );
  }
}
