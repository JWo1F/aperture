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
      shape: RoundedRectangleBorder(
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
    final mono = AppTheme.mono(size: 11.5, color: AppColors.textPrimary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
          child: Row(
            children: [
              Text(
                'Pending edits',
                style: AppTheme.ui(
                  size: 13,
                  weight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${statements.length}',
                  style: AppTheme.mono(
                    size: 11,
                    color: AppColors.accent,
                    weight: FontWeight.w600,
                  ),
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
        Divider(height: 1, color: AppColors.hairline),
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
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: statements.length,
                  itemBuilder: (_, i) => _StatementItem(
                    sql: statements[i],
                    monoStyle: mono,
                  ),
                ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: AppColors.bgDeep,
            border: Border(top: BorderSide(color: AppColors.hairline)),
          ),
          child: Row(
            children: [
              Text(
                'Runs in a single transaction on Apply.',
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

/// One row of the design's `.pe-item` — relation name + ctid header, then a
/// surface-bg SQL block with syntax highlighting.
class _StatementItem extends StatelessWidget {
  const _StatementItem({required this.sql, required this.monoStyle});

  final String sql;
  final TextStyle monoStyle;

  static final _relRe =
      RegExp(r'UPDATE\s+("?[\w.]+"?\."?[\w.]+"?|"?[\w.]+"?)\s', caseSensitive: false);
  static final _ctidRe =
      RegExp(r"ctid\s*=\s*'\(([\d,]+)\)'", caseSensitive: false);

  ({String? relation, String? ctid}) _meta() {
    final r = _relRe.firstMatch(sql)?.group(1);
    final c = _ctidRe.firstMatch(sql)?.group(1);
    return (relation: r, ctid: c == null ? null : '($c)');
  }

  void _copy() => Clipboard.setData(ClipboardData(text: sql));

  @override
  Widget build(BuildContext context) {
    final meta = _meta();
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.edit_outlined, size: 11, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(
                meta.relation ?? 'unknown',
                style: AppTheme.mono(
                  size: 11,
                  color: AppColors.textPrimary,
                  weight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (meta.ctid != null)
                Text(
                  'ctid ${meta.ctid}',
                  style: AppTheme.mono(
                    size: 10.5,
                    color: AppColors.text4,
                  ),
                ),
              const SizedBox(width: 8),
              Hoverable(
                onTap: _copy,
                builder: (context, hovering) => Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: hovering
                        ? AppColors.surfaceHover
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Icon(
                    Icons.copy,
                    size: 11,
                    color: hovering
                        ? AppColors.textPrimary
                        : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgDeep,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
