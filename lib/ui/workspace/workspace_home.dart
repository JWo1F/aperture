import 'package:flutter/material.dart';

import '../../models/db_object.dart';
import '../../state/app_globals.dart';
import '../../state/connection_views.dart';
import '../../theme/app_theme.dart';
import '../command_palette/command_palette.dart';
import 'workspace_home/header.dart';
import 'workspace_home/metrics.dart';
import 'workspace_home/relations_panel.dart';
import 'workspace_home/schemas_panel.dart';
import 'workspace_home/side_panels.dart';

/// The connected-but-nothing-open workspace screen: a static overview of the
/// database — catalog totals, every relation in a sortable list, the schema
/// breakdown, and the connection's recent tables, saved queries and runs.
class WorkspaceHome extends StatefulWidget {
  const WorkspaceHome({super.key});

  @override
  State<WorkspaceHome> createState() => _WorkspaceHomeState();
}

class _WorkspaceHomeState extends State<WorkspaceHome> {
  static const _recentRunsLimit = 6;

  /// Schema the relations panel is scoped to, picked in the schemas panel.
  String? _schema;

  @override
  Widget build(BuildContext context) {
    // The store is watched for the saved-query and run lists; the session's
    // connection snapshot lags behind them.
    return ListenableBuilder(
      listenable: Listenable.merge([
        appState.session,
        appState.catalog,
        appState.store,
      ]),
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final session = appState.session;
    final catalog = appState.catalog;
    final tabs = appState.tabsController;
    final active = session.activeConnection;
    final conn = active == null
        ? null
        : appState.store.connectionById(active.id) ?? active;
    final tint = AppColors.connectionTint(conn?.color);

    final relations = [for (final s in catalog.schemas) ...s.tables];
    final schema = catalog.schemas.any((s) => s.name == _schema)
        ? _schema
        : null;
    final loading = catalog.schemas.isEmpty && catalog.isPhase1Loading;

    final recents = recentTablesView(conn, catalog);
    final frequent = frequentTablesView(conn, catalog, limit: 6);

    final queries = conn?.savedQueries ?? const [];
    final byId = {for (final q in queries) q.id: q};
    final runs = <HomeRun>[
      for (final e in (conn?.queryMessages ?? const {}).entries)
        for (final m in e.value) (message: m, query: byId[e.key]),
    ]..sort((a, b) => b.message.timestamp.compareTo(a.message.timestamp));

    return ColoredBox(
      color: AppColors.bg,
      // The platform default on macOS is iOS-style elastic overscroll, which
      // on a page barely taller than the window reads as the content
      // snapping back. The desktop scroll behavior already supplies the
      // scrollbar.
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final twoColumn = width >= 940;

                  final relationsPanel = RelationsPanel(
                    relations: relations,
                    schema: schema,
                    onClearSchema: () => setState(() => _schema = null),
                    onOpen: tabs.openTable,
                    loading: loading,
                    error: catalog.lastError,
                    showSchemaColumn:
                        catalog.schemas.length > 1 && width >= 560,
                    tint: tint,
                  );
                  final schemasPanel = catalog.schemas.length > 1
                      ? SchemasPanel(
                          schemas: catalog.schemas,
                          selected: schema,
                          onSelect: (s) => setState(() => _schema = s),
                          tint: tint,
                        )
                      : null;
                  final side = <Widget>[
                    JumpBackPanel(
                      tables: recents.isNotEmpty ? recents : frequent,
                      frequent: recents.isEmpty && frequent.isNotEmpty,
                      tint: tint,
                      onOpen: tabs.openTable,
                    ),
                    SavedQueriesPanel(
                      queries: queries,
                      onOpen: tabs.openSavedQuery,
                      onNew: tabs.newQueryTab,
                    ),
                    RecentRunsPanel(
                      runs: runs.take(_recentRunsLimit).toList(),
                      onOpen: tabs.openSavedQuery,
                    ),
                  ];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      HomeHeader(
                        connection: conn,
                        tint: tint,
                        serverVersion: session.serverVersion,
                        refreshing: catalog.isPhase1Loading,
                        onRefresh: appState.refreshCatalog,
                        onSearch: () => showCommandPalette(context),
                        onNewQuery: tabs.newQueryTab,
                        compact: width < 700,
                      ),
                      const SizedBox(height: 20),
                      HomeMetrics(
                        schemas: catalog.schemas.length,
                        tables: relations.where((r) => !r.isView).length,
                        views: relations.where((r) => r.isView).length,
                        rows: _sumOrNull(relations, (r) => r.rowEstimate),
                        bytes: _sumOrNull(relations, (r) => r.sizeBytes),
                        loading: loading,
                        columns: width >= 620 ? 5 : 3,
                      ),
                      const SizedBox(height: 16),
                      if (twoColumn)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: _stack([relationsPanel, ?schemasPanel]),
                            ),
                            const SizedBox(width: 16),
                            Expanded(flex: 2, child: _stack(side)),
                          ],
                        )
                      else
                        _stack([relationsPanel, ...side, ?schemasPanel]),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _stack(List<Widget> panels) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < panels.length; i++) ...[
        if (i > 0) const SizedBox(height: 16),
        panels[i],
      ],
    ],
  );

  /// Null when no relation reports the figure, so the metric shows a dash
  /// rather than a misleading zero.
  static int? _sumOrNull(List<DbTable> relations, int? Function(DbTable) of) {
    int? sum;
    for (final r in relations) {
      final v = of(r);
      if (v != null) sum = (sum ?? 0) + v;
    }
    return sum;
  }
}
