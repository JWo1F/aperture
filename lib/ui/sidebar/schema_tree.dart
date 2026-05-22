import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/count_format.dart';
import '../../models/db_catalog.dart';
import '../../models/db_object.dart';
import '../../state/tabs_controller.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/context_menu.dart';
import '../widgets/table_glyph.dart';
import 'highlighted_text.dart';
import 'saved_query_row.dart';
import 'sidebar_deps.dart';

/// Scrollable body of the connected sidebar: Pinned · Frequent · Queries ·
/// Schemas, with substring filtering and force-expanded schemas when the
/// user is typing in the search bar.
class SidebarBody extends StatelessWidget {
  const SidebarBody({super.key, required this.deps, required this.query});

  final SidebarDeps deps;
  final String query;

  @override
  Widget build(BuildContext context) {
    final activeTableId = _activeTableQualifiedName(deps.tabs);
    final activeQueryId = _activeQueryId(deps.tabs);
    final favKeys = {
      for (final t in deps.perConnection.favoriteTables) t.qualifiedKey,
    };
    final filtering = query.isNotEmpty;

    bool tableMatches(DbTable t) =>
        !filtering ||
        t.name.toLowerCase().contains(query) ||
        t.schema.toLowerCase().contains(query);

    final favList = deps.perConnection.favoriteTables
        .where(tableMatches)
        .toList();
    final frequent = filtering
        ? <DbTable>[]
        : deps.perConnection
              .frequentTables(limit: 5 + favKeys.length)
              .where((t) => !favKeys.contains(t.qualifiedKey))
              .take(5)
              .toList();
    final saved = filtering
        ? deps.perConnection.savedQueries
              .where((q) => q.name.toLowerCase().contains(query))
              .toList()
        : deps.perConnection.savedQueries;

    final visibleSchemas = deps.catalog.schemas.map((s) {
      final tables = filtering
          ? s.tables.where(tableMatches).toList()
          : s.tables;
      return (schema: s, tables: tables);
    }).where((e) => !filtering || e.tables.isNotEmpty).toList();

    final totalTables = deps.catalog.schemas.fold<int>(
      0,
      (a, b) => a + b.tables.length,
    );

    final empty = favList.isEmpty &&
        frequent.isEmpty &&
        saved.isEmpty &&
        visibleSchemas.isEmpty;

    if (empty && filtering) {
      return _NoResults(query: query);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 16),
      children: [
        if (favList.isNotEmpty)
          _Section(
            label: 'Pinned',
            badge: '${favList.length}',
            children: [
              for (final t in favList)
                _TableRow(
                  table: t,
                  deps: deps,
                  active: t.qualifiedName == activeTableId,
                  isFav: true,
                  indent: 0,
                  query: query,
                  scope: 'pin',
                ),
            ],
          ),
        if (frequent.isNotEmpty)
          _Section(
            label: 'Frequent',
            badge: '${frequent.length}',
            children: [
              for (final t in frequent)
                _TableRow(
                  table: t,
                  deps: deps,
                  active: t.qualifiedName == activeTableId,
                  isFav: favKeys.contains(t.qualifiedKey),
                  indent: 0,
                  query: query,
                  scope: 'freq',
                ),
            ],
          ),
        if (saved.isNotEmpty)
          _Section(
            label: 'Queries',
            badge: '${saved.length}',
            children: [
              for (final q in saved)
                SavedQueryRow(
                  query: q,
                  active: q.id == activeQueryId,
                  deps: deps,
                  match: query,
                ),
            ],
          ),
        _Section(
          label: 'Schemas',
          badge: '$totalTables',
          children: [
            for (final entry in visibleSchemas)
              _SchemaBlock(
                schema: entry.schema,
                tables: entry.tables,
                deps: deps,
                activeTableId: activeTableId,
                favKeys: favKeys,
                forceExpanded: filtering,
                query: query,
              ),
          ],
        ),
      ],
    );
  }

  String? _activeTableQualifiedName(TabsController tabs) {
    final tab = tabs.activeTab;
    if (tab is TableTab) return tab.table.qualifiedName;
    if (tab is SchemaTab) return tab.table.qualifiedName;
    return null;
  }

  String? _activeQueryId(TabsController tabs) {
    final tab = tabs.activeTab;
    return tab is QueryTab ? tab.id : null;
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 18,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 8),
          Text(
            'No matches',
            style: AppTheme.ui(
              size: 12.5,
              color: AppColors.textSecondary,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Nothing in this connection matches "$query".',
            style: AppTheme.ui(
              size: 11.5,
              color: AppColors.textMuted,
              weight: FontWeight.w400,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
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

class _SchemaBlock extends StatelessWidget {
  const _SchemaBlock({
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
        _TreeRow(
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
            _TableRow(
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

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.table,
    required this.deps,
    required this.active,
    required this.isFav,
    required this.indent,
    required this.query,
    required this.scope,
  });

  final DbTable table;
  final SidebarDeps deps;
  final bool active;
  final bool isFav;
  final int indent;
  final String query;

  /// Section the row lives in (`pin` / `freq` / `tree`). Folded into the
  /// detail-tree node ids so the same table expanded in one section stays
  /// collapsed in the others.
  final String scope;

  @override
  Widget build(BuildContext context) {
    final tint = AppColors.connectionTint(deps.session.activeConnection?.color);
    final nodeId = '$scope/${table.qualifiedKey}';
    final expanded = deps.ui.isNodeExpanded(nodeId);
    final row = _buildRow(context, tint, expanded, nodeId);
    if (!expanded) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        _TableDetail(
          table: table,
          deps: deps,
          indent: indent + 1,
          scope: scope,
        ),
      ],
    );
  }

  Widget _buildRow(
    BuildContext context,
    Color tint,
    bool expanded,
    String nodeId,
  ) {
    final stat = tableStat(table);
    return _TreeRow(
      indent: indent,
      height: 24,
      active: active,
      tint: tint,
      onTap: () => deps.tabs.openTable(table),
      onSecondaryTapDown: (d) =>
          openTableMenu(context, deps, table, d.globalPosition),
      childrenBuilder: (hovering) {
        final showStar = hovering || isFav;
        return [
          _DetailChevron(
            expanded: expanded,
            onTap: () => deps.ui.toggleNode(nodeId),
          ),
          SizedBox(
            width: 14,
            height: 14,
            child: Center(child: _kindIcon(table.kind, active, tint)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SidebarHighlightedText(
              text: table.name,
              match: query,
              style: AppTheme.ui(
                size: 12,
                color: active
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                weight: active ? FontWeight.w600 : FontWeight.w400,
                letterSpacing: 0,
              ),
            ),
          ),
          if (stat != null) ...[
            const SizedBox(width: 6),
            Text(
              stat,
              style: AppTheme.mono(
                size: 9.5,
                color: AppColors.textSecondary.withValues(alpha: 0.3),
                weight: FontWeight.w400,
              ),
            ),
          ],
          if (showStar)
            _StarToggle(
              filled: isFav,
              onTap: () => deps.perConnection.toggleFavorite(table),
            ),
        ];
      },
    );
  }

  Widget _kindIcon(DbRelationKind kind, bool active, Color tint) {
    switch (kind) {
      case DbRelationKind.table:
        return TableGlyph(
          size: 12,
          color: active ? tint : AppColors.textMuted,
        );
      case DbRelationKind.view:
        return Icon(
          Icons.visibility_outlined,
          size: 12,
          color: active ? tint : AppColors.info,
        );
      case DbRelationKind.materializedView:
        return Icon(
          Icons.layers_outlined,
          size: 12,
          color: active ? tint : AppColors.info,
        );
    }
  }
}

/// Row skeleton shared by every entry in the schema tree (`_SchemaBlock`,
/// `_TableRow`, `_DetailFolder`, `_DetailLeaf`): horizontal margin, hover
/// tint, indent-based left padding, and the optional left rail + tinted
/// background that mark an active selection. Callers supply only the row's
/// inner [children]; pass [childrenBuilder] instead when those children
/// depend on hover state (e.g. a hover-revealed star button).
class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.indent,
    required this.height,
    this.children,
    this.childrenBuilder,
    this.active = false,
    this.tint,
    this.onTap,
    this.onSecondaryTapDown,
    this.padding,
    this.cursor,
  }) : assert(
         (children == null) != (childrenBuilder == null),
         'Provide exactly one of children or childrenBuilder',
       );

  final int indent;
  final double height;
  final List<Widget>? children;
  final List<Widget> Function(bool hovering)? childrenBuilder;
  final bool active;
  final Color? tint;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final EdgeInsetsGeometry? padding;
  final MouseCursor? cursor;

  @override
  Widget build(BuildContext context) {
    final resolvedPadding =
        padding ?? EdgeInsets.only(left: 14.0 + indent * 18.0, right: 6);
    final row = Hoverable(
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTapDown,
      cursor: cursor ?? SystemMouseCursors.click,
      builder: (context, hovering) {
        final activeTint = tint;
        final rowBg = active && activeTint != null
            ? activeTint.withValues(alpha: 0.13)
            : (hovering ? AppColors.sidebarRowHover : Colors.transparent);
        return Container(
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: resolvedPadding,
          decoration: BoxDecoration(
            color: rowBg,
            borderRadius: Radii.brSm,
          ),
          child: Row(
            children: children ?? childrenBuilder!(hovering),
          ),
        );
      },
    );

    if (!active || tint == null) return row;
    final activeTint = tint!;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        row,
        Positioned(
          left: 0,
          top: 5,
          bottom: 5,
          child: Container(
            width: 2.5,
            decoration: BoxDecoration(
              color: activeTint,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(2),
                bottomRight: Radius.circular(2),
              ),
              boxShadow: [
                BoxShadow(
                  color: activeTint.withValues(alpha: 0.45),
                  blurRadius: 6,
                  spreadRadius: 0,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A right-pointing chevron that rotates to point down when [expanded].
/// When [onTap] is set it claims taps itself (so a chevron inside a row
/// whose body has its own gesture can toggle without triggering it);
/// otherwise it is purely decorative and the enclosing row handles the tap.
class _DetailChevron extends StatelessWidget {
  const _DetailChevron({required this.expanded, this.onTap});

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
class _TableDetail extends StatelessWidget {
  const _TableDetail({
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
      return _DetailMessageRow(indent: indent, text: 'Loading details…');
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
          _DetailFolder(
            table: table,
            deps: deps,
            scope: scope,
            indent: indent,
            folder: 'columns',
            count: columns.length,
            children: [
              for (final c in columns)
                _DetailLeaf(
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
          _DetailFolder(
            table: table,
            deps: deps,
            scope: scope,
            indent: indent,
            folder: 'keys',
            count: keys.length,
            children: [
              for (final k in keys)
                _DetailLeaf(
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
          _DetailFolder(
            table: table,
            deps: deps,
            scope: scope,
            indent: indent,
            folder: 'foreign keys',
            count: foreignKeys.length,
            children: [
              for (final fk in foreignKeys)
                _DetailLeaf(
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
          _DetailFolder(
            table: table,
            deps: deps,
            scope: scope,
            indent: indent,
            folder: 'indexes',
            count: indexes.length,
            children: [
              for (final ix in indexes)
                _DetailLeaf(
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
class _DetailFolder extends StatelessWidget {
  const _DetailFolder({
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
        _TreeRow(
          indent: indent,
          height: 24,
          onTap: () => deps.ui.toggleNode(id),
          children: [
            _DetailChevron(expanded: expanded),
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
class _DetailLeaf extends StatelessWidget {
  const _DetailLeaf({
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
    return _TreeRow(
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
class _DetailMessageRow extends StatelessWidget {
  const _DetailMessageRow({required this.indent, required this.text});

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

class _StarToggle extends StatelessWidget {
  const _StarToggle({required this.filled, required this.onTap});

  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) {
        final color = filled
            ? AppColors.warn
            : (hovering ? AppColors.textSecondary : AppColors.text4);
        return Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            filled ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 13,
            color: color,
          ),
        );
      },
    );
  }
}

void openTableMenu(
  BuildContext context,
  SidebarDeps deps,
  DbTable table,
  Offset position,
) {
  final qualified = '"${table.schema}"."${table.name}"';
  final isFav = deps.perConnection.isFavorite(table);

  void copy(String value) => Clipboard.setData(ClipboardData(text: value));

  showContextMenu(
    context,
    globalPosition: position,
    entries: [
      CmItem(
        icon: Icons.north_east,
        label: 'Open data',
        onTap: () => deps.tabs.openTable(table),
      ),
      CmItem(
        icon: Icons.data_object,
        label: 'Show schema (CREATE TABLE)',
        onTap: () => deps.tabs.openSchema(table),
      ),
      const CmDivider(),
      CmItem(
        icon: isFav ? Icons.star : Icons.star_outline,
        label: isFav ? 'Remove from favourites' : 'Add to favourites',
        onTap: () => deps.perConnection.toggleFavorite(table),
      ),
      const CmDivider(),
      CmItem(
        icon: Icons.label_outline,
        label: 'Copy name',
        onTap: () => copy(table.name),
      ),
      CmItem(
        icon: Icons.tag,
        label: 'Copy qualified name',
        onTap: () => copy(qualified),
      ),
      CmItem(
        icon: Icons.code,
        label: 'Copy SELECT *',
        onTap: () => copy('SELECT * FROM $qualified;'),
      ),
      const CmDivider(),
      CmItem(
        icon: Icons.refresh,
        label: 'Refresh catalog',
        onTap: deps.appState.refreshCatalog,
      ),
    ],
  );
}
