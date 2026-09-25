import 'package:flutter/material.dart';

import '../../../models/count_format.dart';
import '../../../theme/app_theme.dart';

/// Catalog totals in one bordered strip. Row and size totals are summed from
/// planner estimates and `pg_total_relation_size`, so they read as "≈" and
/// fall back to a dash when the engine reports neither (SQLite).
class HomeMetrics extends StatelessWidget {
  const HomeMetrics({
    super.key,
    required this.schemas,
    required this.tables,
    required this.views,
    required this.rows,
    required this.bytes,
    required this.loading,
    required this.columns,
  });

  final int schemas;
  final int tables;
  final int views;
  final int? rows;
  final int? bytes;
  final bool loading;

  /// Cells per line; the strip wraps into a grid below five.
  final int columns;

  @override
  Widget build(BuildContext context) {
    String count(int n) => loading ? '—' : withCommas(n);
    final cells = [
      (label: 'Schemas', value: count(schemas)),
      (label: 'Tables', value: count(tables)),
      (label: 'Views', value: count(views)),
      (
        label: 'Rows',
        value: loading || rows == null ? '—' : '≈${compactCount(rows!)}',
      ),
      (
        label: 'On disk',
        value: loading || bytes == null ? '—' : compactBytes(bytes!),
      ),
    ];

    final lines = <List<({String label, String value})>>[
      for (var i = 0; i < cells.length; i += columns)
        cells.sublist(i, (i + columns).clamp(0, cells.length)),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: Radii.brMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var l = 0; l < lines.length; l++)
            Container(
              decoration: l == 0
                  ? null
                  : BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AppColors.borderSoft),
                      ),
                    ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < columns; i++) ...[
                      if (i > 0)
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: AppColors.borderSoft,
                        ),
                      Expanded(
                        child: i < lines[l].length
                            ? _Cell(
                                label: lines[l][i].label,
                                value: lines[l][i].value,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: AppTheme.eyebrow()),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.mono(
              size: 18,
              weight: FontWeight.w600,
              color: AppColors.textPrimary,
            ).copyWith(height: 1.2),
          ),
        ],
      ),
    );
  }
}
