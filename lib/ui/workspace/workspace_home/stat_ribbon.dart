import 'package:flutter/material.dart';

import '../../../models/count_format.dart';
import '../../../theme/app_theme.dart';

class StatRibbon extends StatelessWidget {
  const StatRibbon({
    super.key,
    required this.schemas,
    required this.tables,
    required this.views,
    required this.totalSize,
    required this.loading,
  });

  final int schemas;
  final int tables;
  final int views;
  final int totalSize;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[
      _StatCell(
        value: loading ? '—' : '$schemas',
        label: schemas == 1 ? 'schema' : 'schemas',
      ),
      _StatCell(
        value: loading ? '—' : compactCount(tables),
        label: tables == 1 ? 'table' : 'tables',
      ),
      _StatCell(
        value: loading ? '—' : compactCount(views),
        label: views == 1 ? 'view' : 'views',
      ),
      _StatCell(
        value: loading || totalSize == 0 ? '—' : compactBytes(totalSize),
        label: 'on disk',
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: Radii.brMd,
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0)
              Container(width: 1, height: 30, color: AppColors.border),
            Expanded(child: cells[i]),
          ],
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: AppTheme.mono(
            size: 19,
            weight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 3),
        Text(label.toUpperCase(), style: AppTheme.eyebrow()),
      ],
    );
  }
}
