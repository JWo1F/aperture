import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/db_object.dart';
import '../models/order_term.dart';
import '../models/query_result.dart';
import '../models/saved_query.dart';
import '../models/value_format.dart';
import '../services/db_service.dart';
import '../services/postgres_service.dart';
import 'catalog_controller.dart';
import 'navigation_history.dart';
import 'per_connection_store.dart';
import 'session_controller.dart';
import 'workspace_tab.dart';

/// Owns the workspace tab list, the active index, and per-tab actions
/// (open, close, load page, apply edits, run query, …).
///
/// Per-tab mutable state lives on each [WorkspaceTab]; this controller
/// orchestrates *which* tab a mutation lands on but never touches a tab's
/// collections directly. That keeps notify-on-change inside the tab and
/// removes the "forgot to repaint after mutating" footgun.
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

  List<WorkspaceTab> get tabs => List.unmodifiable(_tabs);

  int get activeIndex => _activeIndex;

  WorkspaceTab? get activeTab =>
      _tabs.isEmpty ? null : _tabs[_activeIndex.clamp(0, _tabs.length - 1)];

  /// Total pending operations (cell edits + row deletes + row inserts)
  /// across every open TableTab.
  int get unappliedEditCount {
    var n = 0;
    for (final t in _tabs) {
      if (t is TableTab) n += t.pendingOpCount;
    }
    return n;
  }

  /// Generates a fresh tab id that does not collide with any open tab or
  /// any persisted saved-query id. SavedQuery ids are produced by this same
  /// counter, but the counter resets to 0 on every app launch — so without
  /// the collision guard, a brand-new TableTab can be assigned the same id
  /// as a previously-saved query, and clicking the query in the sidebar
  /// would land you on the table tab.
  String _nextId() {
    while (true) {
      final candidate = 'id${_idCounter++}';
      if (_tabs.any((t) => t.id == candidate)) continue;
      if (perConnection.savedQueries.any((q) => q.id == candidate)) continue;
      return candidate;
    }
  }

  /// Reset everything when the connection changes (or disconnects).
  void clear() {
    for (final t in _tabs) {
      t.dispose();
    }
    _tabs.clear();
    _activeIndex = 0;
    notifyListeners();
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
    final i = _tabs.indexWhere((t) => t is QueryTab && t.id == id);
    if (i != -1) closeTab(_tabs[i].id);
  }

  void duplicateSavedQuery(String id) {
    perConnection.duplicateSavedQuery(id, _nextId(), _nextQueryName());
  }

  void openSavedQuery(SavedQuery q) {
    final existing = _tabs.indexWhere(
      (t) => t is QueryTab && t.id == q.id,
    );
    if (existing != -1) {
      _select(existing);
      return;
    }
    final tab = QueryTab(q.id, name: q.name, sql: q.sql);
    // Rehydrate the per-tab message log from the connection store so the
    // Messages tab opens populated after a restart.
    tab.hydrateMessages(perConnection.messagesFor(q.id));
    _tabs.add(tab);
    _select(_tabs.length - 1);
  }

  void closeTab(String id) {
    final i = _tabs.indexWhere((t) => t.id == id);
    if (i == -1) return;
    final removed = _tabs.removeAt(i);
    removed.dispose();
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
      if (t.id != keepId) t.dispose();
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
      t.dispose();
    }
    _tabs.removeRange(i + 1, _tabs.length);
    if (_activeIndex >= _tabs.length) _activeIndex = _tabs.length - 1;
    history.pruneTabs(_tabs.map((t) => t.id));
    notifyListeners();
  }

  void closeAllTabs() {
    for (final t in _tabs) {
      t.dispose();
    }
    _tabs.clear();
    _activeIndex = 0;
    history.clear();
    notifyListeners();
  }

  // --- Schema tabs ----------------------------------------------------

  Future<void> openSchema(DbTable table) async {
    final existing = _tabs.indexWhere(
      (t) => t is SchemaTab && t.table.qualifiedName == table.qualifiedName,
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
    if (savedWidths != null) tab.mergeSavedWidths(savedWidths);
    _tabs.add(tab);
    _select(_tabs.length - 1);
    await loadTablePage(tab, 0);
    return tab;
  }

  /// Fetch one page of [tab]'s relation.
  ///
  /// When [clauses] is non-null, the fetch runs against that triple
  /// (filter, selectList, orderBy) instead of the tab's current clauses.
  /// On success, the tab's clauses are swapped to [clauses] together
  /// with the new result — old data and old clauses stay visible until
  /// the fetch returns, then both move in one notification. On failure,
  /// the tab keeps its previous clauses + previous data so the clausebar
  /// never shows clauses that don't match the rows on screen.
  ///
  /// The page index updates eagerly (before the fetch) regardless of
  /// [clauses] — clicking Next while a slow fetch is in flight should
  /// show the new page number immediately. The success vs. failure split
  /// only governs the clause triple.
  Future<void> loadTablePage(
    TableTab tab,
    int page, {
    TableClauses? clauses,
  }) async {
    final service = session.service;
    if (service == null) return;
    final filter = clauses?.filter ?? tab.filter;
    final selectList = clauses?.selectList ?? tab.selectList;
    final orderBy = clauses?.orderBy ?? tab.orderBy;

    tab.loading = true;
    tab.page = page;
    tab.clearEdits();
    notifyListeners();

    try {
      final result = await service.fetchTablePage(
        tab.table,
        limit: tab.pageSize,
        offset: tab.offset,
        filter: filter,
        orderBy: orderBy,
        selectList: selectList,
      );
      if (clauses != null) {
        tab.filter = filter;
        tab.selectList = selectList;
        tab.orderBy = orderBy;
      }
      tab.result = result;
      tab.lastRefreshedAt = DateTime.now();
    } catch (e) {
      tab.result = QueryResult.failure(
        error: e.toString(),
        elapsed: Duration.zero,
      );
    }
    tab.loading = false;
    notifyListeners();

    // The row count can be a full-table scan on large relations; keep it off
    // the critical path so the grid renders as soon as the page arrives.
    unawaited(_refreshRowCount(tab));
  }

  Future<void> _refreshRowCount(TableTab tab) async {
    final service = session.service;
    if (service == null) return;
    final filterAtRequest = tab.filter;
    try {
      final count = await service.countRows(tab.table, filter: filterAtRequest);
      // A slow count can outlive the filter that triggered it; only apply
      // the result if the tab is still showing that same filter.
      if (tab.filter == filterAtRequest) tab.totalRows = count;
    } catch (_) {
      // A failed or timed-out count leaves the previous total in place.
    }
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
    tab.clearColumnWidths();
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
    tab.setAutoRefresh(interval, () {
      if (!_tabs.contains(tab)) return;
      if (tab.running) return;
      final sql = tab.lastRunSql;
      if (sql == null) return;
      unawaited(runQuery(tab, sqlOverride: sql));
    });
  }

  void setTableAutoRefresh(TableTab tab, Duration? interval) {
    tab.setAutoRefresh(interval, () {
      if (!_tabs.contains(tab)) return;
      if (tab.loading || tab.applying || tab.hasEdits) return;
      unawaited(loadTablePage(tab, tab.page));
    });
  }

  void setCellEdit(TableTab tab, int row, int column, CellEditValue value) {
    final result = tab.result;
    if (result == null) return;
    final insertIdx = row - result.rows.length;
    if (insertIdx >= 0) {
      tab.setInsertCellValue(insertIdx, result.columns[column], value);
      return;
    }
    tab.setCellEdit(row, column, value);
  }

  void revertCellEdit(TableTab tab, int row, int column) {
    final result = tab.result;
    if (result == null) return;
    final insertIdx = row - result.rows.length;
    if (insertIdx >= 0) {
      // No "revert" for an insert-row cell — the row itself is what's
      // pending. Use deleteRow / Delete row to discard it.
      return;
    }
    tab.revertCellEdit(row, column);
  }

  void resetTableEdits(TableTab tab) {
    tab.resetAllEdits();
  }

  /// Mark a persistent row for DELETE, or discard a virtual insert row.
  /// Cell edits on the deleted row are dropped — DELETE overrides UPDATE.
  void deleteRow(TableTab tab, int row) {
    final result = tab.result;
    if (result == null) return;
    final insertIdx = row - result.rows.length;
    if (insertIdx >= 0) {
      tab.removeInsertAt(insertIdx);
      return;
    }
    tab.deletePersistentRow(row);
  }

  void restoreDeletedRow(TableTab tab, int row) {
    tab.restoreDeletedRow(row);
  }

  /// Queue a duplicate of [row] as a pending INSERT. Primary-key columns
  /// (resolved through the catalog) are stamped as DEFAULT so the database
  /// generates fresh keys. The new row anchors immediately below its
  /// source so the duplicate is visible in context, not appended at the
  /// far end of the page.
  void duplicateRow(TableTab tab, int row) {
    final result = tab.result;
    if (result == null) return;
    final columns = result.columns;
    final pkColumns = <String>{
      for (final c in (catalog.columnsFor(tab.table) ?? const <DbColumn>[]))
        if (c.isPrimaryKey) c.name,
    };

    final sourceValues = <String, CellEditValue>{};
    int? anchor;
    final insertIdx = row - result.rows.length;
    if (insertIdx >= 0) {
      // Duplicating an existing pending insert — inherit its anchor so the
      // new row sits in the same logical neighborhood as the source.
      if (insertIdx >= tab.inserts.length) return;
      final source = tab.inserts[insertIdx];
      sourceValues.addAll(source.values);
      anchor = source.afterRow;
    } else {
      if (row < 0 || row >= result.rows.length) return;
      anchor = row;
      for (var c = 0; c < columns.length; c++) {
        final pending = tab.edits[CellEdit(row, c)];
        if (pending != null) {
          sourceValues[columns[c]] = pending;
        } else {
          sourceValues[columns[c]] = CellLiteral(
            formatCellValue(result.rows[row][c]),
          );
        }
      }
    }

    final values = <String, CellEditValue>{
      for (final name in columns)
        if (sourceValues.containsKey(name))
          name: pkColumns.contains(name)
              ? const CellDefault()
              : sourceValues[name]!,
    };

    tab.addInsert(PendingInsert(afterRow: anchor, values: values));
  }

  /// Queue a blank pending INSERT anchored below [row]. Every column is
  /// stamped DEFAULT, so the database fills the whole row from its column
  /// defaults. Positions like [duplicateRow] but copies no source values.
  void addRow(TableTab tab, int row) {
    final result = tab.result;
    if (result == null) return;

    int? anchor;
    final insertIdx = row - result.rows.length;
    if (insertIdx >= 0) {
      if (insertIdx >= tab.inserts.length) return;
      anchor = tab.inserts[insertIdx].afterRow;
    } else {
      if (row < 0 || row >= result.rows.length) return;
      anchor = row;
    }

    final values = <String, CellEditValue>{
      for (final name in result.columns) name: const CellDefault(),
    };

    tab.addInsert(PendingInsert(afterRow: anchor, values: values));
  }

  EditBatch _buildBatch(TableTab tab) {
    final result = tab.result;
    if (result == null || result.rowIds == null) return EditBatch();
    final rowIds = result.rowIds!;
    final updates = <String, Map<String, CellEditValue>>{};
    for (final entry in tab.edits.entries) {
      final row = entry.key.row;
      if (row < 0 || row >= rowIds.length) continue;
      if (tab.deletedRows.contains(row)) continue;
      final ctid = rowIds[row];
      final column = result.columns[entry.key.column];
      updates.putIfAbsent(ctid, () => {})[column] = entry.value;
    }
    final deletes = <String>[
      for (final r in tab.deletedRows)
        if (r >= 0 && r < rowIds.length) rowIds[r],
    ];
    return EditBatch(
      updatesByCtid: updates,
      deleteCtids: deletes,
      inserts: tab.snapshotInserts(),
    );
  }

  List<String> previewEditStatements(TableTab tab) {
    final service = session.service;
    if (service == null || !tab.hasEdits) return const [];
    final batch = _buildBatch(tab);
    if (batch.isEmpty) return const [];
    return service.previewEditStatements(tab.table, batch);
  }

  Future<String?> applyTableEdits(TableTab tab) async {
    final service = session.service;
    if (service == null || !tab.hasEdits || tab.applying) return null;
    final result = tab.result;
    if (result == null || result.rowIds == null) {
      return 'This view has no row identity and cannot be edited.';
    }
    final batch = _buildBatch(tab);
    if (batch.isEmpty) return null;

    tab.applying = true;
    notifyListeners();

    String? error;
    try {
      await service.applyTableEdits(tab.table, batch);
    } on StaleRowException catch (e) {
      error = e.toString();
    } on EditFailureException catch (e) {
      error = e.message;
    } catch (e) {
      error = e.toString();
    }
    tab.applying = false;

    if (error == null) {
      tab.resetAllEdits();
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
    tab.appendQueryMessage(
      message,
      maxMessages: PerConnectionStore.maxMessagesPerQuery,
    );
    perConnection.appendQueryMessage(tab.id, message);
    tab.running = false;
    notifyListeners();
  }

  /// Loads or refreshes the EXPLAIN plan for [tab]'s most-recent run.
  ///
  /// Plans `tab.lastRunSql` — the exact statement the Results tab shows —
  /// so the plan and the result set always describe the same query.
  ///
  /// Uses ANALYZE/BUFFERS for plain SELECT, WITH, VALUES, TABLE (so the
  /// times are real numbers, not estimates); falls back to a non-executing
  /// EXPLAIN for statements that would mutate data or aren't planned at all.
  Future<void> loadQueryPlan(QueryTab tab) async {
    final service = session.service;
    final sql = tab.lastRunSql;
    if (service == null || sql == null || sql.trim().isEmpty) return;
    if (tab.planLoading) return;

    // The visual plan reads Postgres' `EXPLAIN (FORMAT JSON)`; SQLite's
    // `EXPLAIN QUERY PLAN` is a different shape entirely.
    if (service is! PostgresService) {
      tab.beginPlan();
      tab.completePlan(
        error: 'The visual query plan is available for PostgreSQL only.',
        sourceSql: sql,
      );
      return;
    }

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
