import 'package:flutter/material.dart';

import '../../models/db_catalog.dart';
import '../../models/db_object.dart';
import '../../theme/app_theme.dart';
import '../widgets/table_glyph.dart';
import 'sidebar_deps.dart';
import 'tree_row.dart';

/// A right-pointing chevron that rotates to point down when [expanded].
/// When [onTap] is set it claims taps itself (so a chevron inside a row
/// whose body has its own gesture can toggle without triggering it);
/// otherwise it is purely decorative and the enclosing row handles the tap.
class DetailChevron extends StatelessWidget {
  const DetailChevron({super.key, required this.expanded, this.onTap});

  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = SizedBox(
      width: 18,
      height: 20,
      child: Center(
        child: AnimatedRotation(
          turns: expanded ? 0.25 : 0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Icon(
            Icons.chevron_right_rounded,
            size: 14,
            color: AppColors.textMuted,
          ),
        ),
      ),
    );
    if (onTap == null) return box;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: box,
    );
  }
}

/// The expanded body of a table row: a `columns / keys / foreign keys /
/// indexes` set of collapsible folders, populated from the live catalog.
class TableDetail extends StatelessWidget {
  const TableDetail({
    super.key,
    required this.table,
    required this.deps,
    required this.indent,
    required this.scope,
  });

  final DbTable table;
  final SidebarDeps deps;
  final int indent;
  final String scope;

  @override
  Widget build(BuildContext context) {
    final catalog = deps.catalog.catalog;
    if (!catalog.hasPhase(CatalogPhase.columns)) {
      return DetailMessageRow(indent: indent, text: 'Loading details…');
    }

    final tint = AppColors.connectionTint(deps.session.activeConnection?.color);
    final columns = catalog.columnsFor(table);
    final keys = catalog.keysFor(table);
    final foreignKeys = catalog.foreignKeysFor(table);
    final indexes = catalog.indexesFor(table);
    final fkColumns = <String>{
      for (final fk in foreignKeys) ...fk.localColumns,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (columns.isNotEmpty)
          DetailFolder(
            table: table,
            deps: deps,
            scope: scope,
            indent: indent,
            folder: 'columns',
            count: columns.length,
            children: [
              for (final c in columns)
                DetailLeaf(
                  indent: indent + 2,
                  leading: ColumnGlyph(
                    size: 12,
                    color: AppColors.textMuted,
                    filled: !c.nullable,
                    mark: c.isPrimaryKey
                        ? ColumnMark.primaryKey
                        : (fkColumns.contains(c.name)
                              ? ColumnMark.foreignKey
                              : ColumnMark.none),
                    markColor: c.isPrimaryKey
                        ? tint
                        : (fkColumns.contains(c.name)
                              ? AppColors.info
                              : null),
                  ),
                  name: c.name,
                  detail: c.dataType,
                ),
            ],
          ),
        if (keys.isNotEmpty)
          DetailFolder(
            table: table,
            deps: deps,
            scope: scope,
            indent: indent,
            folder: 'keys',
            count: keys.length,
            children: [
              for (final k in keys)
                DetailLeaf(
                  indent: indent + 2,
                  leading: Icon(
                    Icons.key_rounded,
                    size: 12,
                    color: k.isPrimary ? tint : AppColors.textMuted,
                  ),
                  name: k.name,
                  detail:
                      '(${k.columns.join(', ')})'
                      '${k.isPrimary ? '' : '  ·  UNIQUE'}',
                ),
            ],
          ),
        if (foreignKeys.isNotEmpty)
          DetailFolder(
            table: table,
            deps: deps,
            scope: scope,
            indent: indent,
            folder: 'foreign keys',
            count: foreignKeys.length,
            children: [
              for (final fk in foreignKeys)
                DetailLeaf(
                  indent: indent + 2,
                  leading: Icon(
                    Icons.link_rounded,
                    size: 12,
                    color: AppColors.info,
                  ),
                  name: fk.constraintName,
                  detail:
                      '(${fk.localColumns.join(', ')}) → ${fk.refTable}',
                  onTap: () {
                    final ref = catalog.relation(fk.refTableOid);
                    if (ref != null) deps.tabs.openTable(ref);
                  },
                ),
            ],
          ),
        if (indexes.isNotEmpty)
          DetailFolder(
            table: table,
            deps: deps,
            scope: scope,
            indent: indent,
            folder: 'indexes',
            count: indexes.length,
            children: [
              for (final ix in indexes)
                DetailLeaf(
                  indent: indent + 2,
                  leading: Icon(
                    Icons.bolt_rounded,
                    size: 12,
                    color: AppColors.textMuted,
                  ),
                  name: ix.name,
                  detail:
                      '(${ix.columns.join(', ')})'
                      '${ix.unique ? '  ·  UNIQUE' : ''}',
                ),
            ],
          ),
      ],
    );
  }
}

/// One collapsible folder ("columns", "indexes", …) under a table.
class DetailFolder extends StatelessWidget {
  const DetailFolder({
    super.key,
    required this.table,
    required this.deps,
    required this.scope,
    required this.indent,
    required this.folder,
    required this.count,
    required this.children,
  });

  final DbTable table;
  final SidebarDeps deps;
  final String scope;
  final int indent;
  final String folder;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final id = '$scope/${table.qualifiedKey}/$folder';
    final expanded = deps.ui.isNodeExpanded(id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TreeRow(
          indent: indent,
          height: 24,
          onTap: () => deps.ui.toggleNode(id),
          children: [
            DetailChevron(expanded: expanded),
            Icon(
              Icons.folder_outlined,
              size: 13,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                folder,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.ui(
                  size: 12,
                  color: AppColors.textSecondary,
                  weight: FontWeight.w400,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: AppTheme.ui(
                size: 10,
                color: AppColors.text4,
                weight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
        if (expanded) ...children,
      ],
    );
  }
}

/// A leaf in the table tree: one column, key, foreign key or index. Carries
/// an [onTap] only for foreign keys, which navigate to the referenced table.
class DetailLeaf extends StatelessWidget {
  const DetailLeaf({
    super.key,
    required this.indent,
    required this.leading,
    required this.name,
    this.detail,
    this.onTap,
  });

  final int indent;
  final Widget leading;
  final String name;
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TreeRow(
      indent: indent,
      height: 22,
      onTap: onTap,
      cursor: onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      children: [
        SizedBox(
          width: 12,
          height: 12,
          child: Center(child: leading),
        ),
        const SizedBox(width: 8),
        // Name and detail share one paragraph so the ellipsis trims the
        // trailing detail first — the name keeps priority for the row's
        // width instead of being capped at an even flex split.
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: name,
                  style: AppTheme.ui(
                    size: 12,
                    color: AppColors.textSecondary,
                    weight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
                if (detail != null)
                  TextSpan(
                    text: '  $detail',
                    style: AppTheme.mono(
                      size: 9.5,
                      color: AppColors.textMuted,
                      weight: FontWeight.w400,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Placeholder row shown while phase-1 introspection is still in flight.
class DetailMessageRow extends StatelessWidget {
  const DetailMessageRow({
    super.key,
    required this.indent,
    required this.text,
  });

  final int indent;
  final String text;

  @override
  Widget build(BuildContext context) {
    final leftBase = 14.0 + indent * 18.0 + 18.0;
    return Container(
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: EdgeInsets.only(left: leftBase, right: 6),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: AppTheme.ui(
          size: 12,
          color: AppColors.textMuted,
          weight: FontWeight.w400,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
