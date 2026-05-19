import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';

import '../../theme/app_theme.dart';
import '../../theme/code_theme.dart';
import '../widgets/common.dart';

/// Read-only preview of the UPDATE statements that pending edits would
/// produce. Lets the user verify the SQL before pressing Apply.
Future<void> showPendingEditsModal(
  BuildContext context, {
  required List<String> statements,
}) {
  return showDialog(
    context: context,
    barrierColor: const Color(0x88000000),
    builder: (_) => Dialog(
      backgroundColor: AppColors.surface,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: Radii.brLg,
        side: BorderSide(color: AppColors.borderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 560),
        child: _Body(statements: statements),
      ),
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.statements});
  final List<String> statements;

  void _copyAll() {
    final joined = statements.map((s) => '$s;').join('\n\n');
    Clipboard.setData(ClipboardData(text: joined));
  }

  @override
  Widget build(BuildContext context) {
    final mono = AppTheme.mono(size: 12, color: AppColors.textPrimary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.lg, 12, 10, 12),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: Radii.brSm,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${statements.length}',
                  style: AppTheme.mono(
                    size: 11,
                    color: AppColors.accent,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                statements.length == 1
                    ? 'Pending statement'
                    : 'Pending statements',
                style: AppTheme.ui(
                  size: 13.5,
                  weight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              IconAction(
                icon: Icons.copy,
                tooltip: 'Copy all',
                onPressed: statements.isEmpty ? null : _copyAll,
              ),
              IconAction(
                icon: Icons.close,
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        Flexible(
          child: statements.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'No pending edits.',
                      style: AppTheme.ui(color: AppColors.textMuted),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(Insets.md),
                  itemCount: statements.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _StatementCard(
                    index: i + 1,
                    sql: statements[i],
                    monoStyle: mono,
                  ),
                ),
        ),
        const Divider(height: 1, color: AppColors.border),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.md,
            vertical: 10,
          ),
          child: Row(
            children: [
              Text(
                'These statements run in a single transaction when you click Apply.',
                style: AppTheme.ui(size: 11, color: AppColors.textMuted),
              ),
              const Spacer(),
              AppButton(
                label: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatementCard extends StatelessWidget {
  const _StatementCard({
    required this.index,
    required this.sql,
    required this.monoStyle,
  });

  final int index;
  final String sql;
  final TextStyle monoStyle;

  void _copy() => Clipboard.setData(ClipboardData(text: sql));

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: Radii.brMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.only(
                topLeft: Radii.sm,
                topRight: Radii.sm,
              ),
              border: Border(
                bottom: BorderSide(color: AppColors.border),
              ),
            ),
            child: Row(
              children: [
                Text(
                  '#$index',
                  style: AppTheme.mono(
                    size: 10,
                    color: AppColors.textMuted,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'UPDATE',
                  style: AppTheme.mono(
                    size: 10,
                    color: AppColors.sqlKeyword,
                    weight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _copy,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.copy,
                        size: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectionArea(
              child: HighlightView(
                sql,
                language: 'pgsql',
                theme: apertureCodeStyles,
                textStyle: monoStyle,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
