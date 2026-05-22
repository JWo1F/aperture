import 'package:flutter/material.dart';

import '../../models/db_object.dart';
import '../../theme/app_theme.dart';
import 'highlighted_text.dart';
import 'sidebar_deps.dart';
import 'table_row.dart';
import 'tree_row.dart';

class SidebarSection extends StatelessWidget {
  const SidebarSection({
    super.key,
    required this.label,
    required this.badge,
    required this.children,
  });

  final String label;
  final String badge;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Row(
            children: [
              Text(
                label.toUpperCase(),
                style: AppTheme.ui(
                  size: 9.5,
                  color: AppColors.textMuted,
                  weight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(height: 1, color: AppColors.hairline),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: const BorderRadius.all(Radii.xs),
                  border: Border.all(color: AppColors.borderSoft),
                ),
                child: Text(
                  badge,
                  style: AppTheme.ui(
                    size: 9.5,
                    color: AppColors.text4,
                    weight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
        ...children,
      ],
    );
  }
}

class SchemaBlock extends StatelessWidget {
  const SchemaBlock({
    super.key,
    required this.schema,
    required this.tables,
    required this.deps,
    required this.activeTableId,
    required this.favKeys,
    required this.forceExpanded,
    required this.query,
  });

  final DbSchema schema;
  final List<DbTable> tables;
  final SidebarDeps deps;
  final String? activeTableId;
  final Set<String> favKeys;
  final bool forceExpanded;
  final String query;

  @override
  Widget build(BuildContext context) {
    final expanded = forceExpanded || deps.ui.isSchemaExpanded(schema.name);
    final tint = AppColors.connectionTint(deps.session.activeConnection?.color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TreeRow(
          indent: 0,
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          onTap: () => deps.ui.toggleSchema(schema.name),
          children: [
            AnimatedRotation(
              turns: expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: expanded
                    ? tint.withValues(alpha: 0.16)
                    : AppColors.surface,
                borderRadius: const BorderRadius.all(Radii.xs),
                border: Border.all(
                  color: expanded
                      ? tint.withValues(alpha: 0.5)
                      : AppColors.borderSoft,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                schema.name.isEmpty
                    ? '?'
                    : schema.name.substring(0, 1).toUpperCase(),
                style: AppTheme.ui(
                  size: 8.5,
                  color: expanded ? tint : AppColors.textMuted,
                  weight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SidebarHighlightedText(
                text: schema.name,
                match: query,
                style: AppTheme.ui(
                  size: 12,
                  color: AppColors.textSecondary,
                  weight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
            Text(
              '${tables.length}',
              style: AppTheme.ui(
                size: 10.5,
                color: AppColors.text4,
                weight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
        if (expanded)
          for (final t in tables)
            SchemaTableRow(
              table: t,
              deps: deps,
              active: t.qualifiedName == activeTableId,
              isFav: favKeys.contains(t.qualifiedKey),
              indent: 1,
              query: query,
              scope: 'tree',
            ),
      ],
    );
  }
}
