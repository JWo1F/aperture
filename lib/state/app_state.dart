import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/connection_config.dart';
import '../models/db_object.dart';
import '../models/order_term.dart';
import '../models/query_result.dart';
import '../models/value_format.dart';
import '../services/connection_store.dart';
import '../services/postgres_service.dart';
import 'workspace_tab.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

/// Single source of truth for the app: saved connections, the live session,
/// the introspected catalog, and the open workspace tabs.
class AppState extends ChangeNotifier {
  AppState() {
    unawaited(_hydrate());
  }

  final ConnectionStore _store = ConnectionStore();

  final List<ConnectionConfig> _connections = [];
  List<ConnectionConfig> get connections => List.unmodifiable(_connections);

  /// Top-3 most recently used connections, freshest first. Used to populate
  /// the welcome screen quick-launch cards.
  List<ConnectionConfig> get recentConnections {
    final stamped = _connections
        .where((c) => c.lastConnectedAt != null)
        .toList()
      ..sort(
        (a, b) => b.lastConnectedAt!.compareTo(a.lastConnectedAt!),
      );
    return stamped.take(3).toList();
  }

  Future<void> _hydrate() async {
    final saved = await _store.load();
    if (saved.isEmpty) return;
    _connections
      ..clear()
      ..addAll(saved);
    notifyListeners();
  }

  void _persist() => unawaited(_store.save(_connections));

  PostgresService? _service;
  ConnectionConfig? _activeConnection;
  ConnectionConfig? get activeConnection => _activeConnection;

  ConnectionStatus _status = ConnectionStatus.disconnected;
  ConnectionStatus get status => _status;

  String? _connectionError;
  String? get connectionError => _connectionError;

  List<DbSchema> _schemas = [];
  List<DbSchema> get schemas => _schemas;

  final Set<String> _expandedSchemas = {};
  bool isSchemaExpanded(String name) => _expandedSchemas.contains(name);

  final Map<String, List<DbColumn>> _columnCache = {};
  List<DbColumn>? columnsFor(DbTable table) =>
      _columnCache[table.qualifiedName];

  /// Every column name we've ever loaded — fed into SQL editor autocomplete.
  Iterable<String> get loadedColumnNames =>
      _columnCache.values.expand((cols) => cols.map((c) => c.name));

  final List<WorkspaceTab> _tabs = [];
  List<WorkspaceTab> get tabs => List.unmodifiable(_tabs);

  /// Schema-tree search filter (set from the sidebar input).
  String _sidebarSearch = '';
  String get sidebarSearch => _sidebarSearch;
  void setSidebarSearch(String value) {
    _sidebarSearch = value;
    notifyListeners();
  }

  /// Recently-opened tables, most recent first. Capped — feeds the command
  /// palette and an optional pinned section in the sidebar.
  final List<DbTable> _recents = [];
  List<DbTable> get recents => List.unmodifiable(_recents);
  void _trackRecent(DbTable table) {
    _recents.removeWhere((t) => t.qualifiedName == table.qualifiedName);
    _recents.insert(0, table);
    if (_recents.length > 12) _recents.removeRange(12, _recents.length);
  }

  int _activeTabIndex = 0;
  int get activeTabIndex => _activeTabIndex;
  WorkspaceTab? get activeTab =>
      _tabs.isEmpty ? null : _tabs[_activeTabIndex.clamp(0, _tabs.length - 1)];

  int _idCounter = 0;
  String _nextId() => 'id${_idCounter++}';

  // --- Saved connections -----------------------------------------------

  void addConnection(ConnectionConfig config) {
    _connections.add(config);
    _persist();
    notifyListeners();
  }

  void updateConnection(ConnectionConfig config) {
    final i = _connections.indexWhere((c) => c.id == config.id);
    if (i != -1) {
      _connections[i] = config;
      if (_activeConnection?.id == config.id) _activeConnection = config;
      _persist();
      notifyListeners();
    }
  }

  void removeConnection(String id) {
    _connections.removeWhere((c) => c.id == id);
    _persist();
    notifyListeners();
  }

  // --- Live session ----------------------------------------------------

  Future<void> connect(ConnectionConfig config) async {
    await _service?.close();
    _service = PostgresService(config);
    _activeConnection = config;
    _status = ConnectionStatus.connecting;
    _connectionError = null;
    _schemas = [];
    _tabs.clear();
    _columnCache.clear();
    notifyListeners();

    try {
      await _service!.connect();
      _schemas = await _service!.loadSchemas();
      if (_schemas.length == 1) _expandedSchemas.add(_schemas.first.name);
      _status = ConnectionStatus.connected;
      // Stamp the connection time so the welcome screen can surface recents.
      final stamped = config.copyWith(lastConnectedAt: DateTime.now());
      final idx = _connections.indexWhere((c) => c.id == config.id);
      if (idx != -1) _connections[idx] = stamped;
      _activeConnection = stamped;
      _persist();
    } catch (e) {
      _status = ConnectionStatus.error;
      _connectionError = e.toString();
      _service = null;
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _service?.close();
    _service = null;
    _activeConnection = null;
    _status = ConnectionStatus.disconnected;
    _schemas = [];
    _expandedSchemas.clear();
    _columnCache.clear();
    _tabs.clear();
    notifyListeners();
  }

  Future<void> refreshSchemas() async {
    if (_service == null) return;
    _schemas = await _service!.loadSchemas();
    notifyListeners();
  }

  // --- Schema tree -----------------------------------------------------

  void toggleSchema(String name) {
    if (!_expandedSchemas.remove(name)) _expandedSchemas.add(name);
    notifyListeners();
  }

  Future<void> ensureColumns(DbTable table) async {
    if (_service == null || _columnCache.containsKey(table.qualifiedName)) {
      return;
    }
    _columnCache[table.qualifiedName] = await _service!.loadColumns(table);
    notifyListeners();
  }

  // --- Workspace tabs --------------------------------------------------

  void _selectTab(int index) {
    _activeTabIndex = index;
    notifyListeners();
  }

  void selectTab(int index) => _selectTab(index);

  void newQueryTab() {
    _tabs.add(QueryTab(_nextId()));
    _selectTab(_tabs.length - 1);
  }

  void closeTab(String id) {
    final i = _tabs.indexWhere((t) => t.id == id);
    if (i == -1) return;
    _tabs.removeAt(i);
    if (_activeTabIndex >= _tabs.length) {
      _activeTabIndex = _tabs.isEmpty ? 0 : _tabs.length - 1;
    }
    notifyListeners();
  }

  /// Closes everything except [keepId], leaving that tab active.
  void closeOtherTabs(String keepId) {
    final keep = _tabs.firstWhere(
      (t) => t.id == keepId,
      orElse: () => throw StateError('Tab not found'),
    );
    _tabs
      ..clear()
      ..add(keep);
    _activeTabIndex = 0;
    notifyListeners();
  }

  /// Closes every tab to the right of [anchorId] (inclusive of its right).
  void closeTabsToRight(String anchorId) {
    final i = _tabs.indexWhere((t) => t.id == anchorId);
    if (i == -1 || i == _tabs.length - 1) return;
    _tabs.removeRange(i + 1, _tabs.length);
    if (_activeTabIndex >= _tabs.length) {
      _activeTabIndex = _tabs.length - 1;
    }
    notifyListeners();
  }

  void closeAllTabs() {
    _tabs.clear();
    _activeTabIndex = 0;
    notifyListeners();
  }

  /// Opens (or focuses) a SchemaTab showing the table's DDL.
  Future<void> openSchema(DbTable table) async {
    final existing = _tabs.indexWhere(
      (t) =>
          t is SchemaTab && t.table.qualifiedName == table.qualifiedName,
    );
    if (existing != -1) {
      _selectTab(existing);
      return;
    }

    final tab = SchemaTab(_nextId(), table);
    _tabs.add(tab);
    _selectTab(_tabs.length - 1);

    if (_service == null) return;
    tab.loading = true;
    notifyListeners();
    try {
      tab.ddl = await _service!.loadTableDdl(table);
    } catch (e) {
      tab.error = e.toString();
    }
    tab.loading = false;
    notifyListeners();
  }

  // --- favorites -------------------------------------------------------

  bool isFavorite(DbTable table) {
    final keys = _activeConnection?.favoriteTables ?? const <String>{};
    return keys.contains(table.qualifiedKey);
  }

  /// Toggles a table in the active connection's favourites and persists.
  void toggleFavorite(DbTable table) {
    final conn = _activeConnection;
    if (conn == null) return;
    final key = table.qualifiedKey;
    final next = Set<String>.of(conn.favoriteTables);
    if (!next.add(key)) next.remove(key);
    final updated = conn.copyWith(favoriteTables: next);
    final i = _connections.indexWhere((c) => c.id == conn.id);
    if (i != -1) _connections[i] = updated;
    _activeConnection = updated;
    _persist();
    notifyListeners();
  }

  /// Materialises the active connection's favourite keys back into [DbTable]s
  /// that exist in the currently-loaded catalog.
  List<DbTable> get favoriteTables {
    final keys = _activeConnection?.favoriteTables;
    if (keys == null || keys.isEmpty) return const [];
    final lookup = <String, DbTable>{
      for (final s in _schemas)
        for (final t in s.tables) t.qualifiedKey: t,
    };
    return [
      for (final key in keys)
        if (lookup[key] != null) lookup[key]!,
    ];
  }

  /// Re-runs the DDL fetch for an open SchemaTab.
  Future<void> reloadSchema(SchemaTab tab) async {
    if (_service == null) return;
    tab.loading = true;
    tab.error = null;
    notifyListeners();
    try {
      tab.ddl = await _service!.loadTableDdl(tab.table);
    } catch (e) {
      tab.error = e.toString();
    }
    tab.loading = false;
    notifyListeners();
  }

  Future<void> openTable(DbTable table) async {
    _trackRecent(table);
    final existing = _tabs.indexWhere(
      (t) => t is TableTab && t.table.qualifiedName == table.qualifiedName,
    );
    if (existing != -1) {
      _selectTab(existing);
      return;
    }

    final tab = TableTab(_nextId(), table);
    _tabs.add(tab);
    _selectTab(_tabs.length - 1);
    await loadTablePage(tab, 0);
  }

  Future<void> loadTablePage(TableTab tab, int page) async {
    if (_service == null) return;
    tab.loading = true;
    tab.page = page;
    tab.edits.clear();
    notifyListeners();

    try {
      tab.totalRows =
          await _service!.countRows(tab.table, filter: tab.filter);
      tab.result = await _service!.fetchTablePage(
        tab.table,
        limit: tab.pageSize,
        offset: tab.offset,
        filter: tab.filter,
        orderBy: tab.orderBy,
        selectList: tab.selectList,
      );
    } catch (e) {
      tab.result = QueryResult.failure(error: e.toString(), elapsed: Duration.zero);
    }
    tab.loading = false;
    notifyListeners();
  }

  /// Fetches every row currently matching the tab's filter + sort. Used by
  /// the exporter when the user chooses "All filtered rows".
  Future<QueryResult> fetchAllForExport(TableTab tab) {
    final service = _service;
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

  /// Sets the column projection and reloads from the first page. Empty
  /// resets to `*`. Edits and column widths are cleared because the column
  /// set may change.
  Future<void> setTableSelect(TableTab tab, String selectList) async {
    final next = selectList.trim().isEmpty ? '*' : selectList.trim();
    if (next == tab.selectList) return;
    tab.selectList = next;
    tab.columnWidths.clear();
    await loadTablePage(tab, 0);
  }

  /// Sets the row filter and reloads from the first page.
  Future<void> setTableFilter(TableTab tab, String filter) async {
    tab.filter = filter;
    await loadTablePage(tab, 0);
  }

  /// Sets the sort and reloads from the first page.
  Future<void> setTableOrder(TableTab tab, String orderBy) async {
    tab.orderBy = orderBy;
    await loadTablePage(tab, 0);
  }

  /// Cycles a column's sort state from a header click, then reloads.
  Future<void> cycleTableOrder(TableTab tab, String column) async {
    final cycled = cycleOrder(parseOrderBy(tab.orderBy), column);
    await setTableOrder(tab, renderOrderBy(cycled));
  }

  /// Sets a column's sort to an explicit direction (used by the cell context
  /// menu). Replaces an existing entry, or appends if absent.
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

  /// Records or clears a pending cell edit. Editing a cell back to its
  /// original value drops the pending change.
  void setCellEdit(TableTab tab, int row, int column, CellEditValue value) {
    final result = tab.result;
    if (result == null) return;
    final original = result.rows[row][column];
    final originalText = formatCellValue(original);
    final key = CellEdit(row, column);

    final matchesOriginal = value is CellLiteral &&
        value.value == originalText;
    if (matchesOriginal) {
      tab.edits.remove(key);
    } else {
      tab.edits[key] = value;
    }
    notifyListeners();
  }

  /// Drops the pending edit on a single cell.
  void revertCellEdit(TableTab tab, int row, int column) {
    tab.edits.remove(CellEdit(row, column));
    notifyListeners();
  }

  void resetTableEdits(TableTab tab) {
    tab.edits.clear();
    notifyListeners();
  }

  /// Renders the SQL UPDATE statements that would be sent if the user clicked
  /// Apply. Pure — does not touch the database.
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

  /// Adds a WHERE fragment via AND.
  Future<void> appendTableFilter(TableTab tab, String fragment) async {
    final trimmed = fragment.trim();
    if (trimmed.isEmpty) return;
    final next = tab.filter.trim().isEmpty
        ? trimmed
        : '${tab.filter.trim()} AND $trimmed';
    await setTableFilter(tab, next);
  }

  /// Commits all pending edits for [tab] as UPDATE statements, then reloads
  /// the current page so the grid reflects the committed state.
  Future<String?> applyTableEdits(TableTab tab) async {
    if (_service == null || !tab.hasEdits || tab.applying) return null;
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
      await _service!.applyTableEdits(tab.table, updates);
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

  Future<void> runQuery(QueryTab tab) async {
    if (_service == null || tab.sql.trim().isEmpty || tab.running) return;
    tab.running = true;
    notifyListeners();

    tab.result = await _service!.runQuery(tab.sql);
    tab.running = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _service?.close();
    super.dispose();
  }
}
