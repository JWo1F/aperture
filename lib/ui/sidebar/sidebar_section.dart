import 'package:flutter/material.dart';

import '../../models/db_object.dart';
import '../../models/schema_object.dart';
import '../../state/app_globals.dart';
import '../../theme/app_theme.dart';
import '../../theme/hugeicons.dart';
import 'highlighted_text.dart';
import 'object_group.dart';
import 'schema_contents.dart';
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
    required this.contents,
    required this.activeTableId,
    required this.favKeys,
    required this.forceExpanded,
    required this.query,
  });

  final SchemaContents contents;
  final String? activeTableId;
  final Set<String> favKeys;
  final bool forceExpanded;
  final String query;

  DbSchema get schema => contents.schema;

  @override
  Widget build(BuildContext context) {
    final expanded =
        forceExpanded || appState.ui.isSchemaExpanded(schema.name);
    final tint =
        AppColors.connectionTint(appState.session.activeConnection?.color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TreeRow(
          indent: 0,
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          onTap: () => appState.ui.toggleSchema(schema.name),
          children: [
            AnimatedRotation(
              turns: expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: Icon(
                Hgi.chevronRight,
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
              '${contents.count}',
              style: AppTheme.ui(
                size: 10.5,
                color: AppColors.text4,
                weight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
        if (expanded) ..._groups(),
      ],
    );
  }

  List<Widget> _groups() {
    final c = contents;
    Widget group(
      String key,
      String label,
      List<Widget> rows, {
      bool expandedByDefault = false,
    }) => SchemaObjectGroup(
      id: 'group/${schema.name}/$key',
      label: label,
      count: rows.length,
      indent: 1,
      forceExpanded: forceExpanded,
      expandedByDefault: expandedByDefault,
      children: rows,
    );

    List<Widget> relations(List<DbTable> tables) => [
      for (final t in tables)
        SchemaTableRow(
          table: t,
          active: t.qualifiedName == activeTableId,
          isFav: favKeys.contains(t.qualifiedKey),
          indent: 2,
          query: query,
          scope: 'tree',
        ),
    ];

    Widget routine(DbRoutine r) => SchemaObjectRow(
      indent: 2,
      icon: r.kind == DbRoutineKind.procedure
          ? Hgi.playSquare
          : Hgi.functionSquare,
      iconColor: AppColors.sqlFunction,
      name: r.name,
      qualifiedName: r.qualifiedName,
      query: query,
      detail: r.result == null
          ? '(${r.arguments})'
          : '(${r.arguments}) → ${r.result}',
      onOpen: () => appState.tabsController.openObject(RoutineObject(r)),
    );

    final types = <(String, Widget)>[
      for (final e in c.enums)
        (
          e.name,
          SchemaObjectRow(
            indent: 2,
            icon: Hgi.listView,
            iconColor: AppColors.tStr,
            name: e.name,
            qualifiedName: e.qualifiedName,
            query: query,
            detail: 'enum · ${e.labels.length}',
            onOpen: () => appState.tabsController.openObject(EnumObject(e)),
          ),
        ),
      for (final d in c.domains)
        (
          d.name,
          SchemaObjectRow(
            indent: 2,
            icon: Hgi.shapes,
            iconColor: AppColors.tUuid,
            name: d.name,
            qualifiedName: d.qualifiedName,
            query: query,
            detail: d.baseType,
            onOpen: () => appState.tabsController.openObject(DomainObject(d)),
          ),
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    return [
      if (c.tables.isNotEmpty)
        group('tables', 'tables', relations(c.tables), expandedByDefault: true),
      if (c.partitioned.isNotEmpty)
        group('partitioned', 'partitioned tables', relations(c.partitioned)),
      if (c.views.isNotEmpty) group('views', 'views', relations(c.views)),
      if (c.materializedViews.isNotEmpty)
        group('matviews', 'materialized views', relations(c.materializedViews)),
      if (c.functions.isNotEmpty)
        group('functions', 'functions', [
          for (final r in c.functions) routine(r),
        ]),
      if (c.procedures.isNotEmpty)
        group('procedures', 'procedures', [
          for (final r in c.procedures) routine(r),
        ]),
      if (c.sequences.isNotEmpty)
        group('sequences', 'sequences', [
          for (final q in c.sequences)
            SchemaObjectRow(
              indent: 2,
              icon: Hgi.sortingOne9,
              iconColor: AppColors.tNum,
              name: q.name,
              qualifiedName: q.qualifiedName,
              query: query,
              onOpen: () => appState.tabsController.openObject(SequenceObject(q)),
            ),
        ]),
      if (types.isNotEmpty)
        group('types', 'types', [for (final t in types) t.$2]),
    ];
  }
}
