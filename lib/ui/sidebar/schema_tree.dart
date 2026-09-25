import 'package:flutter/material.dart';

import '../../models/db_object.dart';
import '../../state/app_globals.dart';
import '../../state/connection_views.dart';
import '../../state/tabs_controller.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../../theme/hugeicons.dart';
import 'saved_query_row.dart';
import 'schema_contents.dart';
import 'sidebar_section.dart';
import 'table_row.dart';

/// Scrollable body of the connected sidebar: Pinned · Frequent · Queries ·
/// Schemas, with substring filtering and force-expanded schemas when the
/// user is typing in the search bar.
class SidebarBody extends StatelessWidget {
  const SidebarBody({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final tabs = appState.tabsController;
    final catalog = appState.catalog;
    final session = appState.session;
    final activeTableId = _activeTableQualifiedName(tabs);
    final activeQueryId = _activeQueryId(tabs);
    final activeConn = session.activeConnection;
    final favorites = favoriteTablesView(activeConn, catalog);
    final favKeys = {for (final t in favorites) t.qualifiedKey};
    final filtering = query.isNotEmpty;

    bool tableMatches(DbTable t) =>
        !filtering ||
        t.name.toLowerCase().contains(query) ||
        t.schema.toLowerCase().contains(query);

    final favList = favorites.where(tableMatches).toList();
    final frequent = filtering
        ? <DbTable>[]
        : frequentTablesView(
            activeConn,
            catalog,
            limit: 5 + favKeys.length,
          )
              .where((t) => !favKeys.contains(t.qualifiedKey))
              .take(5)
              .toList();
    final savedAll = activeConn?.savedQueries ?? const [];
    final saved = filtering
        ? savedAll.where((q) => q.name.toLowerCase().contains(query)).toList()
        : savedAll;

    final visibleSchemas = groupSchemaContents(catalog.catalog, query);

    final totalTables = catalog.schemas.fold<int>(
      0,
      (a, b) => a + b.tables.length,
    );

    final catalogError = catalog.lastError;

    final empty = favList.isEmpty &&
        frequent.isEmpty &&
        saved.isEmpty &&
        visibleSchemas.isEmpty;

    final Widget body;
    if (empty && filtering) {
      body = _NoResults(query: query);
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(0, 2, 0, 16),
        children: [
          if (favList.isNotEmpty)
            SidebarSection(
              label: 'Pinned',
              badge: '${favList.length}',
              children: [
                for (final t in favList)
                  SchemaTableRow(
                    table: t,
                    active: t.qualifiedName == activeTableId,
                    isFav: true,
                    indent: 0,
                    query: query,
                    scope: 'pin',
                  ),
              ],
            ),
          if (frequent.isNotEmpty)
            SidebarSection(
              label: 'Frequent',
              badge: '${frequent.length}',
              children: [
                for (final t in frequent)
                  SchemaTableRow(
                    table: t,
                    active: t.qualifiedName == activeTableId,
                    isFav: favKeys.contains(t.qualifiedKey),
                    indent: 0,
                    query: query,
                    scope: 'freq',
                  ),
              ],
            ),
          if (saved.isNotEmpty)
            SidebarSection(
              label: 'Queries',
              badge: '${saved.length}',
              children: [
                for (final q in saved)
                  SavedQueryRow(
                    query: q,
                    active: q.id == activeQueryId,
                    match: query,
                  ),
              ],
            ),
          SidebarSection(
            label: 'Schemas',
            badge: '$totalTables',
            children: [
              if (catalogError != null)
                _CatalogErrorNotice(error: catalogError),
              for (final contents in visibleSchemas)
                SchemaBlock(
                  contents: contents,
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

    // Slim indeterminate bar pinned above the body while phase 1 fills in
    // columns / FKs / indexes / enums / domains. The schema tree is already
    // usable once phase 0 lands; this is a hint that table views opened
    // right away may still be filling in.
    return Column(
      children: [
        SizedBox(
          height: 2,
          child: catalog.isPhase1Loading
              ? LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation(AppColors.accent),
                )
              : null,
        ),
        Expanded(child: body),
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

/// Slim banner shown inside the Schemas section when introspection
/// failed. Without this the sidebar is indistinguishable from a
/// legitimately-empty database after a phase-0 fetch error.
class _CatalogErrorNotice extends StatelessWidget {
  const _CatalogErrorNotice({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Hgi.alertCircle,
            size: 13,
            color: AppColors.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Couldn't load schemas",
                  style: AppTheme.ui(
                    size: 11.5,
                    color: AppColors.textSecondary,
                    weight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  error.toString(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.ui(
                    size: 10.5,
                    color: AppColors.textMuted,
                    weight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
            Hgi.searchRemove,
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
