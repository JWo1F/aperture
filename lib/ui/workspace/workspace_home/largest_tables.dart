import 'package:flutter/material.dart';

import '../../../models/count_format.dart';
import '../../../models/db_object.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/table_glyph.dart';
import 'section.dart';

class LargestTables extends StatelessWidget {
  const LargestTables({
    super.key,
    required this.tables,
    required this.tint,
    required this.onOpen,
  });

  final List<DbTable> tables;
  final Color tint;
  final void Function(DbTable) onOpen;

  @override
  Widget build(BuildContext context) {
    final max = tables.first.sizeBytes!.toDouble();
    return HomeSection(
      title: 'Largest tables',
      count: tables.length,
      child: Column(
        children: [
          for (final t in tables)
            _SizeBar(
              table: t,
              fraction: max <= 0 ? 0 : t.sizeBytes! / max,
              tint: tint,
              onTap: () => onOpen(t),
            ),
        ],
      ),
    );
  }
}

class _SizeBar extends StatelessWidget {
  const _SizeBar({
    required this.table,
    required this.fraction,
    required this.tint,
    required this.onTap,
  });

  final DbTable table;
  final double fraction;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => Container(
        height: 34,
        margin: const EdgeInsets.only(top: 6),
        child: Stack(
          children: [
            // Proportional fill — the storage bar.
            FractionallySizedBox(
              widthFactor: fraction.clamp(0.02, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: Radii.brSm,
                  gradient: LinearGradient(
                    colors: [
                      tint.withValues(alpha: hovering ? 0.32 : 0.22),
                      tint.withValues(alpha: hovering ? 0.14 : 0.08),
                    ],
                  ),
                ),
              ),
            ),
            // Hairline frame + leading accent.
            Container(
              decoration: BoxDecoration(
                borderRadius: Radii.brSm,
                border: Border.all(
                  color: hovering
                      ? tint.withValues(alpha: 0.5)
                      : AppColors.border,
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    TableGlyph(
                      size: 12,
                      color: table.isView ? AppColors.tDate : tint,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        table.qualifiedKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.mono(
                          size: 11.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (table.rowEstimate != null) ...[
                      Text(
                        '${compactCount(table.rowEstimate!)} rows',
                        style: AppTheme.mono(
                          size: 10,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      compactBytes(table.sizeBytes!),
                      style: AppTheme.mono(
                        size: 11,
                        weight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
