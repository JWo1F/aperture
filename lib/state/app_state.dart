import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/connection_config.dart';
import '../models/db_object.dart';
import '../models/query_result.dart';
import '../models/saved_query.dart';
import '../models/value_format.dart';
import '../theme/app_theme.dart';
import 'catalog_controller.dart';
import 'connection_registry.dart';
import 'event_log.dart';
import 'navigation_history.dart';
import 'per_connection_store.dart';
import 'preferences_controller.dart';
import 'session_controller.dart';
import 'tabs_controller.dart';
import 'workspace_tab.dart';
import 'workspace_ui.dart';

export 'session_controller.dart' show ConnectionStatus;

/// Coordinator over the focused controllers that make up the app's state.
///
/// Each concern (preferences, connection registry, live session, catalog,
/// per-connection bags, tabs, navigation history, schema-tree UI) lives in
/// its own [ChangeNotifier]. [AppState] owns one instance of each, wires
/// cross-controller flows (e.g. connect → bump catalog generation → reset
/// tabs → clear navigation history), and re-broadcasts every child's
/// notifications so existing UI bindings that watch `AppState` continue to
/// work without churn.
///
/// New UI code is encouraged to watch the specific controller it cares
/// about instead (via `context.watch<TabsController>()` or similar) to
/// avoid rebuilding on unrelated state changes.
class AppState extends ChangeNotifier {
  AppState() {
    _children = [
      preferences,
      registry,
      session,
      catalog,
      perConnection,
      tabsController,
      history,
      ui,
      eventLog,
    ];
    for (final c in _children) {
      c.addListener(notifyListeners);
    }
    unawaited(_hydrate());
  }

  final PreferencesController preferences = PreferencesController();
  final ConnectionRegistry registry = ConnectionRegistry();
  final EventLog eventLog = EventLog();
  late final SessionController session = SessionController(log: eventLog);
  final CatalogController catalog = CatalogController();
  final NavigationHistory history = NavigationHistory();
  final WorkspaceUi ui = WorkspaceUi();

  late final PerConnectionStore perConnection = PerConnectionStore(
    session: session,
    registry: registry,
    catalog: catalog,
  );

  late final TabsController tabsController = TabsController(
    session: session,
    catalog: catalog,
    history: history,
    perConnection: perConnection,
  );

  late final List<ChangeNotifier> _children;

  Future<void> _hydrate() async {
    await preferences.hydrate();
    await registry.hydrate();
  }

  // --- Preferences ------------------------------------------------------

  AppBrightness get brightness => preferences.brightness;
  void setBrightness(AppBrightness value) => preferences.setBrightness(value);
  void toggleBrightness() => preferences.toggleBrightness();

  bool get sidebarVisible => preferences.sidebarVisible;
  void toggleSidebar() => preferences.toggleSidebar();

  // --- Connection registry ---------------------------------------------

  List<ConnectionConfig> get connections => registry.all;
  List<ConnectionConfig> get recentConnections => registry.recent;

  void addConnection(ConnectionConfig config) => registry.add(config);
  void updateConnection(ConnectionConfig config) {
    registry.update(config);
    if (session.activeConnection?.id == config.id) {
      session.setActiveConnection(config);
    }
  }

  void removeConnection(String id) => registry.remove(id);

  // --- Session ---------------------------------------------------------

  ConnectionConfig? get activeConnection => session.activeConnection;
  ConnectionStatus get status => session.status;
  String? get connectionError => session.error;
  String? get serverVersion => session.serverVersion;

  Future<void> connect(ConnectionConfig config) async {
    final gen = catalog.beginGeneration();
    tabsController.clear();
    history.clear();

    final ok = await session.connect(config);
    if (!ok) return;
    if (gen != catalog.generation) return;

    try {
      final svc = session.service!;
      final schemas = await catalog.runPhase0(svc, gen);
      if (schemas == null) return;
      if (schemas.length == 1) ui.expandSingleSchema(schemas.first.name);

      final stamped = config.copyWith(lastConnectedAt: DateTime.now());
      registry.update(stamped);
      session.setActiveConnection(stamped);

      // Phase 1 runs in the background; the listener on catalog will fire
      // when it lands.
      unawaited(catalog.runPhase1(svc, gen));
    } catch (_) {
      // Phase 0 fetch failed even though the connect succeeded — fall
      // back to phase-0-empty so the UI shows the connection without
      // data. The caller can refresh.
    }
  }

  Future<void> disconnect() async {
    await session.disconnect();
    catalog.reset();
    ui.reset();
    tabsController.clear();
    history.clear();
  }

  /// Reopen the dropped connection without disturbing the workspace.
  ///
  /// Reloads the catalog (OIDs can shift across server restarts) but
  /// keeps the open tabs and navigation history intact, so the user
  /// recovers to roughly where they were.
  Future<void> reconnect() async {
    final ok = await session.reconnect();
    if (!ok) return;
    final svc = session.service;
    if (svc == null) return;
    final gen = catalog.beginGeneration();
    try {
      final schemas = await catalog.runPhase0(svc, gen);
      if (schemas == null) return;
      unawaited(catalog.runPhase1(svc, gen));
    } catch (_) {
      // catalog.lastError will carry the failure for the UI to display.
    }
  }

  Future<void> refreshCatalog() async {
    final svc = session.service;
    if (svc == null) return;
    final gen = catalog.beginGeneration();
    try {
      final schemas = await catalog.runPhase0(svc, gen);
      if (schemas == null) return;
      await catalog.runPhase1(svc, gen);
    } catch (_) {
      // Surface left on catalog.lastError; UI can show a retry.
    }
  }

  // --- Catalog ---------------------------------------------------------

  List<DbSchema> get schemas => catalog.schemas;
  bool get isCatalogLoading => catalog.isPhase1Loading;
  bool isSchemaExpanded(String name) => ui.isSchemaExpanded(name);
  List<DbColumn>? columnsFor(DbTable table) => catalog.columnsFor(table);
  Map<String, DbForeignKey>? foreignKeysFor(DbTable table) =>
      catalog.foreignKeysFor(table);
  Map<String, DbForeignKey> get aggregatedForeignKeys =>
      catalog.aggregatedForeignKeys;
  DbForeignKey? findForeignKey(int? sourceRelOid, String columnName) =>
      catalog.findForeignKey(sourceRelOid, columnName);
  DbTable? findPrimaryKeyOwner(String columnName) =>
      catalog.findPrimaryKeyOwner(columnName);
  DbTable? findPrimaryKeyOwnerByOid(int? sourceRelOid, String columnName) =>
      catalog.findPrimaryKeyOwnerByOid(sourceRelOid, columnName);
  Iterable<String> get loadedColumnNames => catalog.allColumnNames;

  Future<void> ensureColumns(DbTable table) async {}

  // --- Schema tree -----------------------------------------------------

  String get sidebarSearch => ui.sidebarSearch;
  void setSidebarSearch(String value) => ui.setSidebarSearch(value);
  void toggleSchema(String name) => ui.toggleSchema(name);

  // --- Tabs ------------------------------------------------------------

  List<WorkspaceTab> get tabs => tabsController.tabs;
  int get activeTabIndex => tabsController.activeIndex;
  WorkspaceTab? get activeTab => tabsController.activeTab;
  int get unappliedEditCount => tabsController.unappliedEditCount;

  void newQueryTab() => tabsController.newQueryTab();
  void selectTab(int index) => tabsController.selectTab(index);
  void closeTab(String id) => tabsController.closeTab(id);
  void closeOtherTabs(String keepId) => tabsController.closeOtherTabs(keepId);
  void closeTabsToRight(String anchorId) => tabsController.closeTabsToRight(anchorId);
  void closeAllTabs() => tabsController.closeAllTabs();

  Future<void> openSchema(DbTable table) => tabsController.openSchema(table);
  Future<void> reloadSchema(SchemaTab tab) => tabsController.reloadSchema(tab);
  Future<TableTab> openTable(DbTable table) =>
      tabsController.openTable(table);
  void openSavedQuery(SavedQuery q) => tabsController.openSavedQuery(q);

  Future<void> loadTablePage(TableTab tab, int page) =>
      tabsController.loadTablePage(tab, page);
  Future<QueryResult> fetchAllForExport(TableTab tab) =>
      tabsController.fetchAllForExport(tab);
  Future<void> refreshTable(TableTab tab) => tabsController.refreshTable(tab);

  Future<void> setTableSelect(TableTab tab, String selectList) =>
      tabsController.setTableSelect(tab, selectList);
  Future<void> setTableFilter(TableTab tab, String filter) =>
      tabsController.setTableFilter(tab, filter);
  Future<void> setTableOrder(TableTab tab, String orderBy) =>
      tabsController.setTableOrder(tab, orderBy);
  Future<void> cycleTableOrder(TableTab tab, String column) =>
      tabsController.cycleTableOrder(tab, column);
  Future<void> setColumnSort(TableTab tab, String column, bool descending) =>
      tabsController.setColumnSort(tab, column, descending);
  Future<void> appendTableFilter(TableTab tab, String fragment) =>
      tabsController.appendTableFilter(tab, fragment);
  void setTableAutoRefresh(TableTab tab, Duration? interval) =>
      tabsController.setTableAutoRefresh(tab, interval);
  void setQueryAutoRefresh(QueryTab tab, Duration? interval) =>
      tabsController.setQueryAutoRefresh(tab, interval);

  void setCellEdit(TableTab tab, int row, int column, CellEditValue value) =>
      tabsController.setCellEdit(tab, row, column, value);
  void revertCellEdit(TableTab tab, int row, int column) =>
      tabsController.revertCellEdit(tab, row, column);
  void resetTableEdits(TableTab tab) => tabsController.resetTableEdits(tab);
  List<String> previewEditStatements(TableTab tab) =>
      tabsController.previewEditStatements(tab);
  Future<String?> applyTableEdits(TableTab tab) => tabsController.applyTableEdits(tab);

  Future<void> runQuery(QueryTab tab, {String? sqlOverride}) =>
      tabsController.runQuery(tab, sqlOverride: sqlOverride);
  Future<void> loadQueryPlan(QueryTab tab, {String? sqlOverride}) =>
      tabsController.loadQueryPlan(tab, sqlOverride: sqlOverride);
  void clearQueryMessages(QueryTab tab) {
    tab.messages.clear();
    perConnection.clearQueryMessages(tab.id);
    tab.markChanged();
  }

  void updateQuerySql(QueryTab tab, String sql) =>
      tabsController.updateQuerySql(tab, sql);
  void renameQuery(String id, String name) => tabsController.renameQuery(id, name);
  void deleteSavedQuery(String id) => tabsController.deleteSavedQuery(id);
  void duplicateSavedQuery(String id) => tabsController.duplicateSavedQuery(id);

  // --- Per-connection bags --------------------------------------------

  List<SavedQuery> get savedQueries => perConnection.savedQueries;
  bool isFavorite(DbTable table) => perConnection.isFavorite(table);
  void toggleFavorite(DbTable table) => perConnection.toggleFavorite(table);
  List<DbTable> get favoriteTables => perConnection.favoriteTables;
  List<DbTable> get recents => perConnection.recents;
  void persistColumnWidth(DbTable table, String column, double width) =>
      perConnection.persistColumnWidth(table, column, width);

  // --- Navigation history ---------------------------------------------

  bool get canGoBack => history.canGoBack;
  bool get canGoForward => history.canGoForward;
  void historyBack() => history.back(_applySnapshot);
  void historyForward() => history.forward(_applySnapshot);

  bool _applySnapshot(NavSnapshot snap) {
    final list = tabsController.tabs;
    final i = list.indexWhere((t) => t.id == snap.tabId);
    if (i == -1) return false;
    tabsController.selectTab(i);
    final tab = list[i];
    if (tab is TableTab && snap.hasTableState) {
      final filterChanged = tab.filter != snap.filter;
      final selectChanged = tab.selectList != snap.selectList;
      final orderChanged = tab.orderBy != snap.orderBy;
      final pageChanged = snap.page != null && tab.page != snap.page;
      tab.filter = snap.filter!;
      tab.selectList = snap.selectList!;
      tab.orderBy = snap.orderBy!;
      if (filterChanged || selectChanged || orderChanged || pageChanged) {
        unawaited(tabsController.loadTablePage(tab, snap.page ?? 0));
      }
    }
    return true;
  }

  // --- Cross-controller helpers ---------------------------------------

  Future<void> findRowInTable(
    DbTable refTable,
    String refColumn,
    Object? value,
  ) async {
    final tab = await tabsController.openTable(refTable);
    await tabsController.setTableFilter(tab, equalityFragment(refColumn, value));
  }

  Future<void> followForeignKey(DbForeignKey fk, Object? value) async {
    if (!fk.isSingleColumn) return;
    final ref = catalog.relation(fk.refTableOid) ??
        catalog.relationByName(fk.refSchema, fk.refTable);
    if (ref == null) return;
    final tab = await tabsController.openTable(ref);
    await tabsController.setTableFilter(tab, equalityFragment(fk.refColumn, value));
  }

  @override
  void dispose() {
    for (final c in _children) {
      c.removeListener(notifyListeners);
    }
    tabsController.dispose();
    perConnection.dispose();
    history.dispose();
    catalog.dispose();
    session.dispose();
    registry.dispose();
    preferences.dispose();
    ui.dispose();
    eventLog.dispose();
    super.dispose();
  }
}

/// Re-export of the [WorkspaceTab] symbol so legacy `state/app_state.dart`
/// importers keep compiling without touching every file.
typedef WorkspaceTabExport = WorkspaceTab;
