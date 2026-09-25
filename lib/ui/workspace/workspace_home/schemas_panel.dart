import 'package:flutter/material.dart';

import '../../../models/count_format.dart';
import '../../../models/db_object.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import 'panel.dart';

/// Per-schema relation counts and storage share. Picking a schema scopes the
/// relations panel to it; picking it again clears the scope.
class SchemasPanel extends StatelessWidget {
  const SchemasPanel({
    super.key,
    required this.schemas,
    required this.selected,
    required this.onSelect,
    required this.tint,
  });

  final List<DbSchema> schemas;
  final String? selected;
  final void Function(String?) onSelect;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final stats = [
      for (final s in schemas)
        (
          name: s.name,
          tables: s.tables.where((t) => !t.isView).length,
          views: s.tables.where((t) => t.isView).length,
          bytes: s.tables.fold<int>(0, (sum, t) => sum + (t.sizeBytes ?? 0)),
        ),
    ];
    final hasSizes = stats.any((s) => s.bytes > 0);
    if (hasSizes) {
      stats.sort((a, b) {
        final c = b.bytes.compareTo(a.bytes);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    }
    final total = stats.fold<int>(0, (sum, s) => sum + s.bytes);

    return HomePanel(
      title: 'Schemas',
      count: schemas.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < stats.length; i++)
            _SchemaRow(
              name: stats[i].name,
              tables: stats[i].tables,
              views: stats[i].views,
              bytes: hasSizes ? stats[i].bytes : null,
              share: total == 0 ? 0 : stats[i].bytes / total,
              selected: stats[i].name == selected,
              divider: i > 0,
              tint: tint,
              onTap: () =>
                  onSelect(stats[i].name == selected ? null : stats[i].name),
            ),
        ],
      ),
    );
  }
}

class _SchemaRow extends StatelessWidget {
  const _SchemaRow({
    required this.name,
    required this.tables,
    required this.views,
    required this.bytes,
    required this.share,
    required this.selected,
    required this.divider,
    required this.tint,
    required this.onTap,
  });

  final String name;
  final int tables;
  final int views;
  final int? bytes;
  final double share;
  final bool selected;
  final bool divider;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final counts = [
      '$tables ${tables == 1 ? 'table' : 'tables'}',
      if (views > 0) '$views ${views == 1 ? 'view' : 'views'}',
    ].join(' · ');
    return HomePanelRow(
      onTap: onTap,
      divider: divider,
      child: Row(
        children: [
          Icon(
            selected ? Hgi.folderOpen : Hgi.folder01,
            size: 14,
            color: selected ? AppColors.accent : AppColors.textMuted,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.mono(
                size: 12,
                color: selected ? AppColors.accent : AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            counts,
            style: AppTheme.ui(
              size: 11,
              weight: FontWeight.w400,
              color: AppColors.textMuted,
              letterSpacing: 0,
            ),
          ),
          if (bytes != null) ...[
            const SizedBox(width: 14),
            ShareBar(
              fraction: share,
              color: tint.withValues(alpha: 0.7),
              width: 56,
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 52,
              child: Text(
                compactBytes(bytes!),
                textAlign: TextAlign.end,
                style: AppTheme.mono(size: 11, color: AppColors.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
