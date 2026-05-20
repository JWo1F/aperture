import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/connection_config.dart';
import '../models/db_object.dart';
import '../models/order_term.dart';
import '../models/query_result.dart';
import '../models/saved_query.dart';
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

  final Map<String, Map<String, DbForeignKey>> _fkCache = {};
  Map<String, DbForeignKey>? foreignKeysFor(DbTable table) =>
      _fkCache[table.qualifiedName];

  /// Union of all loaded tables' FKs, keyed by local column name. Used by
  /// query result grids to offer "Follow →" when an FK column appears in a
  /// raw SQL result. First match wins on collisions (a personal-tool tradeoff
  /// for the much simpler implementation vs. resolving source table OIDs).
  Map<String, DbForeignKey> get aggregatedForeignKeys {
    final out = <String, DbForeignKey>{};
    for (final perTable in _fkCache.values) {
      for (final entry in perTable.entries) {
        out.putIfAbsent(entry.key, () => entry.value);
      }
    }
    return out;
  }

  /// Heuristic lookup: which loaded table treats [columnName] as its (single)
  /// primary key? First match wins. Returns null when no loaded table claims
  /// this column as a PK — in which case the "Find row in table" menu item
  /// is hidden.
  DbTable? findPrimaryKeyOwner(String columnName) {
    for (final entry in _columnCache.entries) {
      final cols = entry.value;
      if (cols.any((c) => c.name == columnName && c.isPrimaryKey)) {
        // Locate the matching DbTable instance in our schemas list.
        for (final s in _schemas) {
          for (final t in s.tables) {
            if (t.qualifiedName == entry.key) return t;
          }
        }
      }
    }
    return null;
  }

  /// Opens (or focuses) [refTable] and filters it to the row where
  /// [refColumn] equals [value]. Used by the "Find row" cell-context action.
  Future<void> findRowInTable(
    DbTable refTable,
    String refColumn,
    dynamic value,
  ) async {
    await openTable(refTable);
    final tab = _tabs.lastWhere(
      (t) =>
          t is TableTab && t.table.qualifiedName == refTable.qualifiedName,
    ) as TableTab;
    await setTableFilter(tab, _equalityFragment(refColumn, value));
  }

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
    _persistRecents();
  }

  void _persistRecents() {
    final conn = _activeConnection;
    if (conn == null) return;
    final keys = _recents.map((t) => t.qualifiedKey).toList();
    if (_listEq(keys, conn.recentTables)) return;
    _replaceActiveConnection(conn.copyWith(recentTables: keys));
  }

  bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _hydrateRecents(ConnectionConfig conn) {
    _recents.clear();
    final lookup = <String, DbTable>{
      for (final s in _schemas)
        for (final t in s.tables) t.qualifiedKey: t,
    };
    for (final key in conn.recentTables) {
      final t = lookup[key];
      if (t != null) _recents.add(t);
    }
  }

  int _activeTabIndex = 0;
  int get activeTabIndex => _activeTabIndex;
  WorkspaceTab? get activeTab =>
      _tabs.isEmpty ? null : _tabs[_activeTabIndex.clamp(0, _tabs.length - 1)];

  int _idCounter = 0;
  String _nextId() => 'id${_idCounter++}';

  // --- navigation history (tabs + per-table filter/sort) --------------

  final List<_NavSnapshot> _navHistory = [];
  int _historyIndex = -1;
  bool _navigatingHistory = false;

  bool get canGoBack => _historyIndex > 0;
  bool get canGoForward => _historyIndex < _navHistory.length - 1;

  void _pushSnapshot(_NavSnapshot snap) {
    if (_navigatingHistory) return;
    if (_historyIndex < _navHistory.length - 1) {
      _navHistory.removeRange(_historyIndex + 1, _navHistory.length);
    }
    if (_navHistory.isEmpty || _navHistory.last != snap) {
      _navHistory.add(snap);
      if (_navHistory.length > 80) _navHistory.removeAt(0);
      _historyIndex = _navHistory.length - 1;
    }
  }

  /// Captures the current state of [tab] (or a plain tab focus) and pushes it.
  void _pushCurrentTab(WorkspaceTab tab) {
    if (tab is TableTab) {
      _pushSnapshot(_NavSnapshot.table(
        tab.id,
        filter: tab.filter,
        selectList: tab.selectList,
        orderBy: tab.orderBy,
      ));
    } else {
      _pushSnapshot(_NavSnapshot.focus(tab.id));
    }
  }

  void historyBack() {
    while (_historyIndex > 0) {
      _historyIndex--;
      if (_applySnapshot(_navHistory[_historyIndex])) return;
    }
  }

  void historyForward() {
    while (_historyIndex < _navHistory.length - 1) {
      _historyIndex++;
      if (_applySnapshot(_navHistory[_historyIndex])) return;
    }
  }

  bool _applySnapshot(_NavSnapshot snap) {
    final i = _tabs.indexWhere((t) => t.id == snap.tabId);
    if (i == -1) return false;
    _navigatingHistory = true;
    _activeTabIndex = i;
    final tab = _tabs[i];
    if (tab is TableTab && snap.hasTableState) {
      final reload = tab.filter != snap.filter ||
          tab.selectList != snap.selectList ||
          tab.orderBy != snap.orderBy;
      tab.filter = snap.filter!;
      tab.selectList = snap.selectList!;
      tab.orderBy = snap.orderBy!;
      if (reload) {
        // Fire-and-forget; loadTablePage doesn't push to history.
        unawaited(loadTablePage(tab, 0));
      }
    }
    _navigatingHistory = false;
    notifyListeners();
    return true;
  }

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
    _navHistory.clear();
    _historyIndex = -1;
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
      _hydrateRecents(stamped);
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
    _navHistory.clear();
    _historyIndex = -1;
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
    if (_service == null) return;
    final key = table.qualifiedName;
    final needCols = !_columnCache.containsKey(key);
    final needFks = !_fkCache.containsKey(key);
    if (!needCols && !needFks) return;
    if (needCols) {
      _columnCache[key] = await _service!.loadColumns(table);
    }
    if (needFks) {
      _fkCache[key] = await _service!.loadForeignKeys(table);
    }
    notifyListeners();
  }

  // --- Workspace tabs --------------------------------------------------

  void _selectTab(int index) {
    _activeTabIndex = index;
    if (index >= 0 && index < _tabs.length) {
      _pushCurrentTab(_tabs[index]);
    }
    notifyListeners();
  }

  void selectTab(int index) => _selectTab(index);

  void newQueryTab() {
    final id = _nextId();
    final tab = QueryTab(id, name: _nextQueryName());
    _tabs.add(tab);
    _selectTab(_tabs.length - 1);
    // New tabs aren't persisted until they have content — keeps the
    // sidebar clean of empty placeholders.
  }

  // --- saved queries ---------------------------------------------------

  List<SavedQuery> get savedQueries =>
      _activeConnection?.savedQueries ?? const [];

  String _nextQueryName() {
    final taken = <String>{
      for (final q in savedQueries) q.name,
      for (final t in _tabs)
        if (t is QueryTab) t.name,
    };
    var n = 1;
    while (taken.contains('Query $n')) {
      n++;
    }
    return 'Query $n';
  }

  /// Push the tab's current state into the active connection's saved-query
  /// list (insert or update) and persist. No-op when no connection is live.
  void _persistQuery(QueryTab tab) {
    final conn = _activeConnection;
    if (conn == null) return;
    final entry = SavedQuery(
      id: tab.id,
      name: tab.name,
      sql: tab.sql,
      updatedAt: DateTime.now(),
    );
    final next = List<SavedQuery>.of(conn.savedQueries);
    final i = next.indexWhere((q) => q.id == tab.id);
    if (i == -1) {
      next.add(entry);
    } else {
      next[i] = entry;
    }
    _replaceActiveConnection(conn.copyWith(savedQueries: next));
  }

  void _replaceActiveConnection(ConnectionConfig updated) {
    final i = _connections.indexWhere((c) => c.id == updated.id);
    if (i != -1) _connections[i] = updated;
    _activeConnection = updated;
    _persist();
    notifyListeners();
  }

  /// Autosave from the query editor — debounced upstream.
  void updateQuerySql(QueryTab tab, String sql) {
    tab.sql = sql;
    _persistQuery(tab);
  }

  void renameQuery(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final conn = _activeConnection;
    if (conn == null) return;
    final list = [
      for (final q in conn.savedQueries)
        if (q.id == id) q.copyWith(name: trimmed) else q,
    ];
    _replaceActiveConnection(conn.copyWith(savedQueries: list));
    // Reflect in any open tab.
    for (final t in _tabs) {
      if (t is QueryTab && t.id == id) t.name = trimmed;
    }
    notifyListeners();
  }

  void deleteSavedQuery(String id) {
    final conn = _activeConnection;
    if (conn == null) return;
    final list = conn.savedQueries.where((q) => q.id != id).toList();
    _replaceActiveConnection(conn.copyWith(savedQueries: list));
    // Close the open tab if any — closeTab notifies on its own.
    closeTab(id);
  }

  void duplicateSavedQuery(String id) {
    final conn = _activeConnection;
    if (conn == null) return;
    final src = conn.savedQueries.firstWhere(
      (q) => q.id == id,
      orElse: () => SavedQuery(id: '', name: '', sql: ''),
    );
    if (src.id.isEmpty) return;
    final copy = SavedQuery(
      id: _nextId(),
      name: _nextQueryName(),
      sql: src.sql,
      updatedAt: DateTime.now(),
    );
    _replaceActiveConnection(
      conn.copyWith(savedQueries: [...conn.savedQueries, copy]),
    );
  }

  /// Opens (or focuses) a saved query as a workspace tab.
  void openSavedQuery(SavedQuery q) {
    final existing = _tabs.indexWhere((t) => t.id == q.id);
    if (existing != -1) {
      _selectTab(existing);
      return;
    }
    final tab = QueryTab(q.id, name: q.name, sql: q.sql);
    _tabs.add(tab);
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
    // Hydrate saved column widths for this table, if any.
    final savedWidths =
        _activeConnection?.columnWidths[table.qualifiedKey];
    if (savedWidths != null) tab.columnWidths.addAll(savedWidths);
    _tabs.add(tab);
    _selectTab(_tabs.length - 1);
    // Catalog metadata first — it's a small query, and having it before the
    // grid is interactive means the cell picker shows the right shape
    // (calendar, time, …) even for NULL cells whose runtime type alone
    // doesn't reveal the column type.
    await ensureColumns(table);
    await loadTablePage(tab, 0);
  }

  // --- column widths persistence ---------------------------------------

  Timer? _widthSaveTimer;
  Map<String, Map<String, double>>? _pendingWidths;

  /// Stores the user's resized [width] for [column] of [table], debounced so a
  /// continuous drag coalesces into one disk write.
  void persistColumnWidth(DbTable table, String column, double width) {
    final conn = _activeConnection;
    if (conn == null) return;

    _pendingWidths ??=
        Map<String, Map<String, double>>.from(conn.columnWidths.map(
      (k, v) => MapEntry(k, Map<String, double>.from(v)),
    ));
    final perTable = _pendingWidths!.putIfAbsent(
      table.qualifiedKey,
      () => <String, double>{},
    );
    perTable[column] = width;

    _widthSaveTimer?.cancel();
    _widthSaveTimer = Timer(const Duration(milliseconds: 500), () {
      final c = _activeConnection;
      final pending = _pendingWidths;
      if (c == null || pending == null) return;
      _pendingWidths = null;
      _replaceActiveConnection(c.copyWith(columnWidths: pending));
    });
  }

  /// Opens (or focuses) the referenced table and filters it down to the row
  /// pointed at by [value]. Used by the cell context menu's "Follow →" item.
  Future<void> followForeignKey(DbForeignKey fk, dynamic value) async {
    final ref = _findTable(fk.refSchema, fk.refTable) ??
        DbTable(
          schema: fk.refSchema,
          name: fk.refTable,
          kind: DbRelationKind.table,
        );
    await openTable(ref);
    final tab = _tabs.lastWhere(
      (t) =>
          t is TableTab && t.table.qualifiedName == ref.qualifiedName,
    ) as TableTab;
    await setTableFilter(tab, _equalityFragment(fk.refColumn, value));
  }

  DbTable? _findTable(String schema, String name) {
    for (final s in _schemas) {
      if (s.name != schema) continue;
      for (final t in s.tables) {
        if (t.name == name) return t;
      }
    }
    return null;
  }

  String _equalityFragment(String column, dynamic value) {
    if (value == null) return '"$column" IS NULL';
    if (value is num || value is BigInt || value is bool) {
      return '"$column" = $value';
    }
    final text = formatCellValue(value) ?? '';
    final escaped = text.replaceAll("'", "''");
    return '"$column" = \'$escaped\'';
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
    _pushCurrentTab(tab);
    await loadTablePage(tab, 0);
  }

  /// Sets the row filter and reloads from the first page.
  Future<void> setTableFilter(TableTab tab, String filter) async {
    if (filter == tab.filter) return;
    tab.filter = filter;
    _pushCurrentTab(tab);
    await loadTablePage(tab, 0);
  }

  /// Sets the sort and reloads from the first page.
  Future<void> setTableOrder(TableTab tab, String orderBy) async {
    if (orderBy == tab.orderBy) return;
    tab.orderBy = orderBy;
    _pushCurrentTab(tab);
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

  Future<void> runQuery(QueryTab tab, {String? sqlOverride}) async {
    final sql = sqlOverride ?? tab.sql;
    if (_service == null || sql.trim().isEmpty || tab.running) return;
    tab.running = true;
    notifyListeners();

    tab.result = await _service!.runQuery(sql);
    tab.running = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _service?.close();
    super.dispose();
  }
}

/// One entry in the navigation history. A snapshot records either a plain
/// tab focus or, for [TableTab]s, the full triple (filter, selectList,
/// orderBy) so ⌘[ undoes filter / sort changes as well as tab switches.
class _NavSnapshot {
  const _NavSnapshot.focus(this.tabId)
      : filter = null,
        selectList = null,
        orderBy = null;

  const _NavSnapshot.table(
    this.tabId, {
    required this.filter,
    required this.selectList,
    required this.orderBy,
  });

  final String tabId;
  final String? filter;
  final String? selectList;
  final String? orderBy;

  bool get hasTableState =>
      filter != null && selectList != null && orderBy != null;

  @override
  bool operator ==(Object other) =>
      other is _NavSnapshot &&
      other.tabId == tabId &&
      other.filter == filter &&
      other.selectList == selectList &&
      other.orderBy == orderBy;

  @override
  int get hashCode => Object.hash(tabId, filter, selectList, orderBy);
}
