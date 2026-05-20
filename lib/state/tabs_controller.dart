import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/db_object.dart';
import '../models/order_term.dart';
import '../models/query_result.dart';
import '../models/saved_query.dart';
import '../models/value_format.dart';
import '../services/postgres_service.dart';
import 'catalog_controller.dart';
import 'navigation_history.dart';
import 'per_connection_store.dart';
import 'session_controller.dart';
import 'workspace_tab.dart';

/// Owns the workspace tab list, the active index, and per-tab actions
/// (open, close, load page, apply edits, run query, …).
///
/// The per-tab state still lives on each [WorkspaceTab] for now; Phase 2.4
/// promotes individual tabs to their own ChangeNotifiers so cell-edit
/// changes only rebuild their tab.
class TabsController extends ChangeNotifier {
  TabsController({
    required this.session,
    required this.catalog,
    required this.history,
    required this.perConnection,
  });

  final SessionController session;
  final CatalogController catalog;
  final NavigationHistory history;
  final PerConnectionStore perConnection;

  final List<WorkspaceTab> _tabs = [];
  int _activeIndex = 0;
  int _idCounter = 0;

  // Auto-refresh timers, keyed by tab id. Will move onto each TableTab in
  // Phase 2.4.
  final Map<String, Timer> _autoRefreshTimers = {};

  List<WorkspaceTab> get tabs => List.unmodifiable(_tabs);
  int get activeIndex => _activeIndex;
  WorkspaceTab? get activeTab =>
      _tabs.isEmpty ? null : _tabs[_activeIndex.clamp(0, _tabs.length - 1)];

  /// Total pending cell edits across every open TableTab.
  int get unappliedEditCount {
    var n = 0;
    for (final t in _tabs) {
      if (t is TableTab) n += t.edits.length;
    }
    return n;
  }

  String _nextId() => 'id${_idCounter++}';

  /// Reset everything when the connection changes (or disconnects).
  void clear() {
    cancelAllAutoRefresh();
    _tabs.clear();
    _activeIndex = 0;
    notifyListeners();
  }

  /// Cancel pending edits clearing across all tabs (e.g. on disconnect).
  void cancelAllAutoRefresh() {
    for (final t in _autoRefreshTimers.values) {
      t.cancel();
    }
    _autoRefreshTimers.clear();
  }

  void _select(int index) {
    _activeIndex = index;
    if (index >= 0 && index < _tabs.length) {
      history.pushTab(_tabs[index]);
    }
    notifyListeners();
  }

  void selectTab(int index) => _select(index);

  void newQueryTab() {
    final tab = QueryTab(_nextId(), name: _nextQueryName());
    _tabs.add(tab);
    _select(_tabs.length - 1);
  }

  String _nextQueryName() {
    final taken = <String>{
      for (final q in perConnection.savedQueries) q.name,
      for (final t in _tabs)
        if (t is QueryTab) t.name,
    };
    var n = 1;
    while (taken.contains('Query $n')) {
      n++;
    }
    return 'Query $n';
  }

  /// Autosave from the query editor — debounced upstream.
  void updateQuerySql(QueryTab tab, String sql) {
    tab.sql = sql;
    perConnection.persistQueryEdit(tab.id, tab.name, sql);
  }

  void renameQuery(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    perConnection.renameQuery(id, trimmed);
    for (final t in _tabs) {
      if (t is QueryTab && t.id == id) t.name = trimmed;
    }
    notifyListeners();
  }

  void deleteSavedQuery(String id) {
    perConnection.deleteSavedQuery(id);
    closeTab(id);
  }

  void duplicateSavedQuery(String id) {
    perConnection.duplicateSavedQuery(id, _nextId(), _nextQueryName());
  }

  void openSavedQuery(SavedQuery q) {
    final existing = _tabs.indexWhere((t) => t.id == q.id);
    if (existing != -1) {
      _select(existing);
      return;
    }
    final tab = QueryTab(q.id, name: q.name, sql: q.sql);
    // Rehydrate the per-tab message log from the connection store so the
    // Messages tab opens populated after a restart.
    final persisted = perConnection.messagesFor(q.id);
    if (persisted.isNotEmpty) tab.messages.addAll(persisted);
    _tabs.add(tab);
    _select(_tabs.length - 1);
  }

  void closeTab(String id) {
    final i = _tabs.indexWhere((t) => t.id == id);
    if (i == -1) return;
    _autoRefreshTimers.remove(id)?.cancel();
    _tabs.removeAt(i);
    if (_activeIndex >= _tabs.length) {
      _activeIndex = _tabs.isEmpty ? 0 : _tabs.length - 1;
    }
    history.pruneTabs(_tabs.map((t) => t.id));
    notifyListeners();
  }

  void closeOtherTabs(String keepId) {
    final keep = _tabs.firstWhere(
      (t) => t.id == keepId,
      orElse: () => throw StateError('Tab not found'),
    );
    for (final t in _tabs) {
      if (t.id != keepId) _autoRefreshTimers.remove(t.id)?.cancel();
    }
    _tabs
      ..clear()
      ..add(keep);
    _activeIndex = 0;
    history.pruneTabs(_tabs.map((t) => t.id));
    notifyListeners();
  }

  void closeTabsToRight(String anchorId) {
    final i = _tabs.indexWhere((t) => t.id == anchorId);
    if (i == -1 || i == _tabs.length - 1) return;
    for (final t in _tabs.sublist(i + 1)) {
      _autoRefreshTimers.remove(t.id)?.cancel();
    }
    _tabs.removeRange(i + 1, _tabs.length);
    if (_activeIndex >= _tabs.length) _activeIndex = _tabs.length - 1;
    history.pruneTabs(_tabs.map((t) => t.id));
    notifyListeners();
  }

  void closeAllTabs() {
    cancelAllAutoRefresh();
    _tabs.clear();
    _activeIndex = 0;
    history.clear();
    notifyListeners();
  }

  // --- Schema tabs ----------------------------------------------------

  Future<void> openSchema(DbTable table) async {
    final existing = _tabs.indexWhere(
      (t) =>
          t is SchemaTab && t.table.qualifiedName == table.qualifiedName,
    );
    if (existing != -1) {
      _select(existing);
      return;
    }
    final tab = SchemaTab(_nextId(), table);
    _tabs.add(tab);
    _select(_tabs.length - 1);

    final service = session.service;
    if (service == null) return;
    tab.loading = true;
    notifyListeners();
    try {
      tab.ddl = await service.loadTableDdl(table);
    } catch (e) {
      tab.error = e.toString();
    }
    tab.loading = false;
    notifyListeners();
  }

  Future<void> reloadSchema(SchemaTab tab) async {
    final service = session.service;
    if (service == null) return;
    tab.loading = true;
    tab.error = null;
    notifyListeners();
    try {
      tab.ddl = await service.loadTableDdl(tab.table);
    } catch (e) {
      tab.error = e.toString();
    }
    tab.loading = false;
    notifyListeners();
  }

  // --- Table tabs ----------------------------------------------------

  Future<TableTab> openTable(DbTable table) async {
    perConnection.trackRecent(table);
    final existing = _tabs.indexWhere(
      (t) => t is TableTab && t.table.qualifiedName == table.qualifiedName,
    );
    if (existing != -1) {
      _select(existing);
      return _tabs[existing] as TableTab;
    }
    final tab = TableTab(_nextId(), table);
    final savedWidths = perConnection.columnWidthsFor(table);
    if (savedWidths != null) tab.columnWidths.addAll(savedWidths);
    _tabs.add(tab);
    _select(_tabs.length - 1);
    await loadTablePage(tab, 0);
    return tab;
  }

  Future<void> loadTablePage(TableTab tab, int page) async {
    final service = session.service;
    if (service == null) return;
    tab.loading = true;
    tab.page = page;
    tab.edits.clear();
    tab.markChanged();
    notifyListeners();

    try {
      tab.totalRows =
          await service.countRows(tab.table, filter: tab.filter);
      tab.result = await service.fetchTablePage(
        tab.table,
        limit: tab.pageSize,
        offset: tab.offset,
        filter: tab.filter,
        orderBy: tab.orderBy,
        selectList: tab.selectList,
      );
      tab.lastRefreshedAt = DateTime.now();
    } catch (e) {
      tab.result =
          QueryResult.failure(error: e.toString(), elapsed: Duration.zero);
    }
    tab.loading = false;
    notifyListeners();
  }

  Future<QueryResult> fetchAllForExport(TableTab tab) {
    final service = session.service;
    if (service == null) {
      throw StateError('Not connected');
    }
    return service.fetchAllTableRows(
      tab.table,
      filter: tab.filter,
      orderBy: tab.orderBy,
      selectList: tab.selectList,
    );
  }

  Future<void> refreshTable(TableTab tab) => loadTablePage(tab, tab.page);

  Future<void> setTableSelect(TableTab tab, String selectList) async {
    final next = selectList.trim().isEmpty ? '*' : selectList.trim();
    if (next == tab.selectList) return;
    tab.selectList = next;
    tab.columnWidths.clear();
    tab.markChanged();
    history.pushTab(tab);
    await loadTablePage(tab, 0);
  }

  Future<void> setTableFilter(TableTab tab, String filter) async {
    if (filter == tab.filter) return;
    tab.filter = filter;
    history.pushTab(tab);
    await loadTablePage(tab, 0);
  }

  Future<void> setTableOrder(TableTab tab, String orderBy) async {
    if (orderBy == tab.orderBy) return;
    tab.orderBy = orderBy;
    history.pushTab(tab);
    await loadTablePage(tab, 0);
  }

  Future<void> cycleTableOrder(TableTab tab, String column) async {
    final cycled = cycleOrder(parseOrderBy(tab.orderBy), column);
    await setTableOrder(tab, renderOrderBy(cycled));
  }

  Future<void> setColumnSort(
    TableTab tab,
    String column,
    bool descending,
  ) async {
    final terms = parseOrderBy(tab.orderBy);
    final next = List<OrderTerm>.of(terms);
    final i = next.indexWhere((t) => t.column == column);
    if (i == -1) {
      next.add(OrderTerm(column, descending));
    } else {
      next[i] = OrderTerm(column, descending);
    }
    await setTableOrder(tab, renderOrderBy(next));
  }

  Future<void> appendTableFilter(TableTab tab, String fragment) async {
    final trimmed = fragment.trim();
    if (trimmed.isEmpty) return;
    final next = tab.filter.trim().isEmpty
        ? trimmed
        : '${tab.filter.trim()} AND $trimmed';
    await setTableFilter(tab, next);
  }

  void setQueryAutoRefresh(QueryTab tab, Duration? interval) {
    _autoRefreshTimers.remove(tab.id)?.cancel();
    tab.autoRefreshInterval = interval;
    if (interval != null) {
      _autoRefreshTimers[tab.id] = Timer.periodic(interval, (_) {
        if (!_tabs.contains(tab)) return;
        if (tab.running) return;
        final sql = tab.lastRunSql;
        if (sql == null) return;
        unawaited(runQuery(tab, sqlOverride: sql));
      });
    }
    notifyListeners();
  }

  void setTableAutoRefresh(TableTab tab, Duration? interval) {
    _autoRefreshTimers.remove(tab.id)?.cancel();
    tab.autoRefreshInterval = interval;
    if (interval != null) {
      _autoRefreshTimers[tab.id] = Timer.periodic(interval, (_) {
        // Bail if the tab was closed between scheduling and firing.
        if (!_tabs.contains(tab)) return;
        if (tab.loading || tab.applying || tab.hasEdits) return;
        unawaited(loadTablePage(tab, tab.page));
      });
    }
    notifyListeners();
  }

  void setCellEdit(TableTab tab, int row, int column, CellEditValue value) {
    final result = tab.result;
    if (result == null) return;
    final original = result.rows[row][column];
    final originalText = formatCellValue(original);
    final key = CellEdit(row, column);
    final matchesOriginal =
        value is CellLiteral && value.value == originalText;
    if (matchesOriginal) {
      tab.edits.remove(key);
    } else {
      tab.edits[key] = value;
    }
    tab.markChanged();
    notifyListeners();
  }

  void revertCellEdit(TableTab tab, int row, int column) {
    tab.edits.remove(CellEdit(row, column));
    tab.markChanged();
    notifyListeners();
  }

  void resetTableEdits(TableTab tab) {
    tab.edits.clear();
    tab.markChanged();
    notifyListeners();
  }

  List<String> previewEditStatements(TableTab tab) {
    final result = tab.result;
    if (result?.rowIds == null || tab.edits.isEmpty) return const [];
    final updates = <String, Map<String, CellEditValue>>{};
    for (final entry in tab.edits.entries) {
      final ctid = result!.rowIds![entry.key.row];
      final column = result.columns[entry.key.column];
      updates.putIfAbsent(ctid, () => {})[column] = entry.value;
    }
    return buildEditStatements(tab.table, updates);
  }

  Future<String?> applyTableEdits(TableTab tab) async {
    final service = session.service;
    if (service == null || !tab.hasEdits || tab.applying) return null;
    final result = tab.result;
    if (result == null || result.rowIds == null) {
      return 'This view has no row identity and cannot be edited.';
    }
    final updates = <String, Map<String, CellEditValue>>{};
    for (final entry in tab.edits.entries) {
      final ctid = result.rowIds![entry.key.row];
      final column = result.columns[entry.key.column];
      updates.putIfAbsent(ctid, () => {})[column] = entry.value;
    }

    tab.applying = true;
    notifyListeners();

    String? error;
    try {
      await service.applyTableEdits(tab.table, updates);
    } on StaleRowException catch (e) {
      error = e.toString();
    } on EditFailureException catch (e) {
      error = e.message;
    } catch (e) {
      error = e.toString();
    }
    tab.applying = false;

    if (error == null) {
      await loadTablePage(tab, tab.page);
    } else {
      notifyListeners();
    }
    return error;
  }

  // --- Query tabs ----------------------------------------------------

  Future<void> runQuery(QueryTab tab, {String? sqlOverride}) async {
    final service = session.service;
    final sql = sqlOverride ?? tab.sql;
    if (service == null || sql.trim().isEmpty || tab.running) return;
    tab.running = true;
    notifyListeners();
    final result = await service.runQuery(sql);
    tab.result = result;
    tab.lastRunSql = sql;
    tab.lastRefreshedAt = DateTime.now();
    // Plan cache is keyed by SQL; a fresh run almost always invalidates it.
    // Skip clearing if we just re-ran the exact statement the plan was
    // computed against — keeps the Plan tab non-stale on auto-refresh.
    if (tab.planSourceSql != sql) tab.clearPlan();
    final message = QueryMessage(
      timestamp: DateTime.now(),
      sql: sql,
      elapsedMs: result.elapsed.inMilliseconds,
      affectedRows: result.affectedRows,
      error: result.isError ? result.error : null,
    );
    tab.messages.add(message);
    if (tab.messages.length > PerConnectionStore.maxMessagesPerQuery) {
      tab.messages.removeRange(
        0,
        tab.messages.length - PerConnectionStore.maxMessagesPerQuery,
      );
    }
    perConnection.appendQueryMessage(tab.id, message);
    tab.running = false;
    notifyListeners();
  }

  /// Loads or refreshes the EXPLAIN plan for [tab].
  ///
  /// When [sqlOverride] is given, plans that exact text instead of the
  /// most-recent run. That powers the Plan tab's "Run as EXPLAIN"
  /// affordance — the user can ask for a plan without having executed
  /// the query first.
  ///
  /// Uses ANALYZE/BUFFERS for plain SELECT, WITH, VALUES, TABLE (so the
  /// times are real numbers, not estimates); falls back to a non-executing
  /// EXPLAIN for statements that would mutate data or aren't planned at all.
  Future<void> loadQueryPlan(QueryTab tab, {String? sqlOverride}) async {
    final service = session.service;
    final sql = sqlOverride ?? tab.lastRunSql;
    if (service == null || sql == null || sql.trim().isEmpty) return;
    if (tab.planLoading) return;
    if (tab.planSourceSql == sql && tab.planJson != null) return;

    tab.beginPlan();

    final trimmed = _stripTrailingSemicolon(sql);
    final analyze = _isExplainAnalyzeSafe(trimmed);
    final options = analyze
        ? '(ANALYZE, BUFFERS, VERBOSE, FORMAT JSON)'
        : '(VERBOSE, FORMAT JSON)';

    try {
      final result = await service.execute('EXPLAIN $options $trimmed');
      final raw = result.first.first;
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! List || decoded.isEmpty) {
        tab.completePlan(
          error: 'EXPLAIN returned an unexpected shape.',
          sourceSql: sql,
        );
        return;
      }
      final top = decoded.first as Map<String, dynamic>;
      tab.completePlan(json: top, sourceSql: sql);
    } catch (e) {
      tab.completePlan(error: e.toString(), sourceSql: sql);
    }
  }

  /// Whether [sql] is safe to run under EXPLAIN ANALYZE — i.e. it's a
  /// pure read. Anything else uses plain EXPLAIN so DML, DDL, and session
  /// commands don't actually fire.
  bool _isExplainAnalyzeSafe(String sql) {
    final stripped = sql.trimLeft().toUpperCase();
    return stripped.startsWith('SELECT') ||
        stripped.startsWith('WITH') ||
        stripped.startsWith('VALUES') ||
        stripped.startsWith('TABLE ');
  }

  String _stripTrailingSemicolon(String sql) {
    var s = sql.trimRight();
    while (s.endsWith(';')) {
      s = s.substring(0, s.length - 1).trimRight();
    }
    return s;
  }
}
