import 'package:flutter/material.dart';

import '../../../models/count_format.dart';
import '../../../models/db_object.dart';
import '../../../models/saved_query.dart';
import '../../../models/time_ago.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import '../../widgets/common.dart';
import '../../widgets/table_glyph.dart';
import 'section.dart';

class JumpAndQueries extends StatelessWidget {
  const JumpAndQueries({
    super.key,
    required this.narrow,
    required this.jumpBack,
    required this.jumpIsFrequent,
    required this.queries,
    required this.tint,
    required this.onOpenTable,
    required this.onOpenQuery,
    required this.onNewQuery,
  });

  final bool narrow;
  final List<DbTable> jumpBack;
  final bool jumpIsFrequent;
  final List<SavedQuery> queries;
  final Color tint;
  final void Function(DbTable) onOpenTable;
  final void Function(SavedQuery) onOpenQuery;
  final VoidCallback onNewQuery;

  @override
  Widget build(BuildContext context) {
    final jump = HomeSection(
      title: jumpIsFrequent ? 'Most visited' : 'Jump back in',
      count: jumpBack.length,
      child: jumpBack.isEmpty
          ? const HomeSectionEmpty(
              icon: Hgi.table01,
              message: 'Open a table from the sidebar and it lands here.',
            )
          : Column(
              children: [
                for (final t in jumpBack.take(6))
                  _TableRow(table: t, tint: tint, onTap: () => onOpenTable(t)),
              ],
            ),
    );

    final saved = HomeSection(
      title: 'Saved queries',
      count: queries.length,
      child: queries.isEmpty
          ? HomeSectionEmpty(
              icon: Hgi.bookmark01,
              message: 'Queries you save show up here.',
              action: HomeTextAction(label: 'New query', onTap: onNewQuery),
            )
          : Column(
              children: [
                for (final q in queries.take(6))
                  _QueryRow(query: q, tint: tint, onTap: () => onOpenQuery(q)),
              ],
            ),
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          jump,
          const SizedBox(height: 20),
          saved,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 5, child: jump),
        const SizedBox(width: 18),
        Expanded(flex: 4, child: saved),
      ],
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.table,
    required this.tint,
    required this.onTap,
  });

  final DbTable table;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stat = tableStat(table);
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        height: 38,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: hovering ? AppColors.surfaceHover : AppColors.surface,
          borderRadius: Radii.brSm,
          border: Border.all(
            color: hovering ? tint.withValues(alpha: 0.4) : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            TableGlyph(
              size: 13,
              color: table.isView ? AppColors.tDate : tint,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    table.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.mono(
                      size: 12,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    table.schema,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.ui(
                      size: 9.5,
                      weight: FontWeight.w400,
                      color: AppColors.textMuted,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            if (stat != null)
              Text(
                stat,
                style: AppTheme.mono(size: 10, color: AppColors.textMuted),
              ),
            const SizedBox(width: 6),
            Icon(
              Hgi.arrowRight01,
              size: 13,
              color: hovering ? tint : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}

class _QueryRow extends StatelessWidget {
  const _QueryRow({
    required this.query,
    required this.tint,
    required this.onTap,
  });

  final SavedQuery query;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = query.sql
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final updated = query.updatedAt;
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        height: 38,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: hovering ? AppColors.surfaceHover : AppColors.surface,
          borderRadius: Radii.brSm,
          border: Border.all(
            color: hovering ? tint.withValues(alpha: 0.4) : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(Hgi.sourceCode, size: 14, color: tint),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    query.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.ui(
                      size: 12,
                      weight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    preview.isEmpty ? 'empty query' : preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.mono(
                      size: 9.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (updated != null) ...[
              const SizedBox(width: 8),
              Text(
                timeAgo(updated),
                style: AppTheme.mono(size: 10, color: AppColors.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
