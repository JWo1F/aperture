import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/cell_edit.dart';
import '../models/db_object.dart';
import '../models/query_message.dart';
import '../models/query_result.dart';
import '../models/value_format.dart';

export '../models/cell_edit.dart'
    show CellEdit, CellEditValue, CellLiteral, CellDefault, PendingInsert, EditBatch;
export '../models/query_message.dart';

/// A tab in the centre workspace. Either a free-form SQL editor, a data
/// view bound to one relation, or a schema viewer.
///
/// Each tab is its own [ChangeNotifier] and owns its mutable state behind
/// methods that internally notify; collections expose unmodifiable views,
/// so a caller can never desync the UI by reaching past a setter.
sealed class WorkspaceTab extends ChangeNotifier {
  WorkspaceTab(this.id);

  final String id;

  final Map<String, double> _columnWidths = {};

  /// Per-tab column widths, keyed by column name. Read-only view; mutate
  /// through [setColumnWidth], [clearColumnWidths], or [mergeSavedWidths].
  late final Map<String, double> columnWidths =
      UnmodifiableMapView(_columnWidths);

  String get title;

  void setColumnWidth(String column, double width) {
    _columnWidths[column] = width;
    notifyListeners();
  }

  void clearColumnWidths() {
    if (_columnWidths.isEmpty) return;
    _columnWidths.clear();
    notifyListeners();
  }

  void mergeSavedWidths(Map<String, double> saved) {
    if (saved.isEmpty) return;
    _columnWidths.addAll(saved);
    notifyListeners();
  }
}

/// Which section of the query tab the user is currently viewing below
/// the editor: the result grid, the plan tree, or the messages log.
enum QueryResultsView { results, plan, messages }

/// The user-facing clause triple on a [TableTab]: WHERE filter, projection
/// (SELECT list), and ORDER BY. Bundled into one value so a clause change
/// can be paired atomically with the fetch that backs it — see
/// `TabsController.loadTablePage`.
class TableClauses {
  const TableClauses({
    required this.filter,
    required this.selectList,
    required this.orderBy,
  });

  final String filter;
  final String selectList;
  final String orderBy;
}

class QueryTab extends WorkspaceTab {
  QueryTab(super.id, {String name = 'Query', String sql = ''})
    : _name = name,
      _sql = sql;

  // ignore_for_file: prefer_initializing_formals
  String _name;
  String _sql;
  QueryResult? _result;
  bool _running = false;
  DateTime? _lastRefreshedAt;
  String? _lastRunSql;
  Duration? _autoRefreshInterval;
  Timer? _autoRefreshTimer;
  QueryResultsView _view = QueryResultsView.results;

  /// Plan-tab state. [planJson] is the top-level node of the parsed JSON
  /// EXPLAIN output. [planError] holds a server-side error if EXPLAIN
  /// failed. [planLoading] flips while the EXPLAIN round-trip is in flight.
  Map<String, dynamic>? _planJson;
  String? _planError;
  bool _planLoading = false;
  String? _planSourceSql;

  final List<QueryMessage> _messages = [];

  /// Per-tab message log — every SQL this tab issued, newest last.
  late final List<QueryMessage> messages = UnmodifiableListView(_messages);

  /// Display name shown in the tab strip + sidebar. User-renamable via
  /// the sidebar context menu; auto-incremented as `Query 1`, `Query 2`,
  /// … when created via the toolbar / ⌘N path.
  String get name => _name;

  set name(String value) {
    if (_name == value) return;
    _name = value;
    notifyListeners();
  }

  String get sql => _sql;

  set sql(String value) {
    if (_sql == value) return;
    _sql = value;
    notifyListeners();
  }

  QueryResult? get result => _result;

  set result(QueryResult? value) {
    _result = value;
    notifyListeners();
  }

  bool get running => _running;

  set running(bool value) {
    if (_running == value) return;
    _running = value;
    notifyListeners();
  }

  /// Wall-clock time the most recent run completed. Powers the "refreshed
  /// HH:MM:SS" stamp in the query pagebar.
  DateTime? get lastRefreshedAt => _lastRefreshedAt;

  set lastRefreshedAt(DateTime? value) {
    _lastRefreshedAt = value;
    notifyListeners();
  }

  /// SQL the most recent run actually sent — may differ from [sql] when the
  /// user invoked Run statement on a single block. The footer's refresh
  /// button re-issues this exact text rather than the whole editor body.
  String? get lastRunSql => _lastRunSql;

  set lastRunSql(String? value) {
    _lastRunSql = value;
    notifyListeners();
  }

  /// Active section below the editor.
  QueryResultsView get view => _view;

  set view(QueryResultsView value) {
    if (_view == value) return;
    _view = value;
    notifyListeners();
  }

  Map<String, dynamic>? get planJson => _planJson;

  String? get planError => _planError;

  bool get planLoading => _planLoading;

  /// SQL the cached plan was computed against. Stays in sync with
  /// [lastRunSql] until the next run, at which point the plan view shows
  /// a stale indicator unless [loadQueryPlan] is invoked again.
  String? get planSourceSql => _planSourceSql;

  /// Reset plan to empty so the next switch into the Plan tab triggers a
  /// fresh EXPLAIN.
  void clearPlan() {
    _planJson = null;
    _planError = null;
    _planLoading = false;
    _planSourceSql = null;
    notifyListeners();
  }

  void beginPlan() {
    _planLoading = true;
    _planError = null;
    notifyListeners();
  }

  void completePlan({
    Map<String, dynamic>? json,
    String? error,
    required String sourceSql,
  }) {
    _planJson = json;
    _planError = error;
    _planLoading = false;
    _planSourceSql = sourceSql;
    notifyListeners();
  }

  /// Auto-refresh cadence. Pair with [setAutoRefresh] to wire the timer.
  Duration? get autoRefreshInterval => _autoRefreshInterval;

  /// Replace the auto-refresh schedule. `null` cancels. The timer lives on
  /// the tab so it shuts down with [dispose]; [onTick] runs every tick
  /// until cancelled.
  void setAutoRefresh(Duration? interval, VoidCallback onTick) {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    _autoRefreshInterval = interval;
    if (interval != null) {
      _autoRefreshTimer = Timer.periodic(interval, (_) => onTick());
    }
    notifyListeners();
  }

  void hydrateMessages(Iterable<QueryMessage> persisted) {
    _messages.addAll(persisted);
    if (_messages.isNotEmpty) notifyListeners();
  }

  void appendQueryMessage(QueryMessage message, {required int maxMessages}) {
    _messages.add(message);
    if (_messages.length > maxMessages) {
      _messages.removeRange(0, _messages.length - maxMessages);
    }
    notifyListeners();
  }

  void clearMessages() {
    if (_messages.isEmpty) return;
    _messages.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  String get title => _name;
}

/// Read-only view of a table's DDL (CREATE TABLE, indexes, FKs).
class SchemaTab extends WorkspaceTab {
  SchemaTab(super.id, this.table);

  final DbTable table;

  String? _ddl;
  String? _error;
  bool _loading = false;

  String? get ddl => _ddl;

  set ddl(String? value) {
    _ddl = value;
    notifyListeners();
  }

  String? get error => _error;

  set error(String? value) {
    _error = value;
    notifyListeners();
  }

  bool get loading => _loading;

  set loading(bool value) {
    if (_loading == value) return;
    _loading = value;
    notifyListeners();
  }

  @override
  String get title => '${table.name} · schema';
}

class TableTab extends WorkspaceTab {
  TableTab(super.id, this.table);

  final DbTable table;

  QueryResult? _result;
  bool _loading = false;
  bool _applying = false;
  int _page = 0;
  int _pageSize = 100;
  int _totalRows = 0;
  String _selectList = '*';
  String _filter = '';
  String _orderBy = '';
  Duration? _autoRefreshInterval;
  Timer? _autoRefreshTimer;
  DateTime? _lastRefreshedAt;

  final Map<CellEdit, CellEditValue> _edits = {};
  final Set<int> _deletedRows = {};
  final List<PendingInsert> _inserts = [];

  /// Pending, un-applied cell edits, keyed by (row, column). Only meaningful
  /// for persistent rows — pending inserts mutate [inserts] directly.
  late final Map<CellEdit, CellEditValue> edits = UnmodifiableMapView(_edits);

  /// Row indexes (into [result.rows]) marked for DELETE on Apply. Cell
  /// edits on a deleted row are dropped — DELETE supersedes UPDATE.
  late final Set<int> deletedRows = UnmodifiableSetView(_deletedRows);

  /// Synthetic rows queued for INSERT. The grid renders them after the
  /// persistent rows so the user can edit their cells inline before Apply.
  late final List<PendingInsert> inserts = UnmodifiableListView(_inserts);

  QueryResult? get result => _result;

  set result(QueryResult? value) {
    _result = value;
    notifyListeners();
  }

  bool get loading => _loading;

  set loading(bool value) {
    if (_loading == value) return;
    _loading = value;
    notifyListeners();
  }

  bool get applying => _applying;

  set applying(bool value) {
    if (_applying == value) return;
    _applying = value;
    notifyListeners();
  }

  int get page => _page;

  set page(int value) {
    if (_page == value) return;
    _page = value;
    notifyListeners();
  }

  int get pageSize => _pageSize;

  set pageSize(int value) {
    if (_pageSize == value) return;
    _pageSize = value;
    notifyListeners();
  }

  int get totalRows => _totalRows;

  set totalRows(int value) {
    if (_totalRows == value) return;
    _totalRows = value;
    notifyListeners();
  }

  /// Column projection — a raw SQL select list. Defaults to `*`.
  String get selectList => _selectList;

  set selectList(String value) {
    if (_selectList == value) return;
    _selectList = value;
    notifyListeners();
  }

  /// Active row filter — a raw SQL `WHERE` fragment typed by the user.
  String get filter => _filter;

  set filter(String value) {
    if (_filter == value) return;
    _filter = value;
    notifyListeners();
  }

  /// Active sort — a raw SQL `ORDER BY` fragment, also driven by header clicks.
  String get orderBy => _orderBy;

  set orderBy(String value) {
    if (_orderBy == value) return;
    _orderBy = value;
    notifyListeners();
  }

  /// Auto-refresh cadence. Pair with [setAutoRefresh] to wire the timer.
  Duration? get autoRefreshInterval => _autoRefreshInterval;

  /// Replace the auto-refresh schedule. `null` cancels. The timer lives on
  /// the tab and is cancelled by [dispose].
  void setAutoRefresh(Duration? interval, VoidCallback onTick) {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    _autoRefreshInterval = interval;
    if (interval != null) {
      _autoRefreshTimer = Timer.periodic(interval, (_) => onTick());
    }
    notifyListeners();
  }

  /// Wall-clock time the most recent page load completed (manual refresh,
  /// auto-refresh, or first open). Drives the "refreshed HH:MM:SS" tag in
  /// the pagination bar.
  DateTime? get lastRefreshedAt => _lastRefreshedAt;

  set lastRefreshedAt(DateTime? value) {
    _lastRefreshedAt = value;
    notifyListeners();
  }

  bool get hasEdits =>
      _edits.isNotEmpty || _deletedRows.isNotEmpty || _inserts.isNotEmpty;

  /// Aggregate count of pending operations (cell edits + row deletes + row
  /// inserts) shown in the pending-edits chip.
  int get pendingOpCount =>
      _edits.length + _deletedRows.length + _inserts.length;

  int get pageCount =>
      _totalRows == 0 ? 1 : ((_totalRows - 1) ~/ _pageSize) + 1;

  int get offset => _page * _pageSize;

  /// Wipe pending cell edits without touching inserts/deletes. Used by
  /// page loads — a fresh page invalidates row-indexed edits.
  void clearEdits() {
    if (_edits.isEmpty) return;
    _edits.clear();
    notifyListeners();
  }

  /// Wipe every pending mutation. Used after a successful Apply and by
  /// the explicit "Reset edits" action.
  void resetAllEdits() {
    if (_edits.isEmpty && _deletedRows.isEmpty && _inserts.isEmpty) return;
    _edits.clear();
    _deletedRows.clear();
    _inserts.clear();
    notifyListeners();
  }

  /// Stage a cell edit on a persistent row. A value equal to the original
  /// (via [formatCellValue]) reverts to "no edit"; otherwise the edit is
  /// recorded under [CellEdit(row, column)].
  void setCellEdit(int row, int column, CellEditValue value) {
    final result = _result;
    if (result == null) return;
    final original = result.rows[row][column];
    final originalText = formatCellValue(original);
    final key = CellEdit(row, column);
    final matchesOriginal = value is CellLiteral && value.value == originalText;
    if (matchesOriginal) {
      _edits.remove(key);
    } else {
      _edits[key] = value;
    }
    notifyListeners();
  }

  void revertCellEdit(int row, int column) {
    if (_edits.remove(CellEdit(row, column)) != null) {
      notifyListeners();
    }
  }

  /// Update a single column value on a pending insert row identified by
  /// its index into [inserts].
  void setInsertCellValue(int insertIdx, String columnName, CellEditValue value) {
    if (insertIdx < 0 || insertIdx >= _inserts.length) return;
    _inserts[insertIdx].values[columnName] = value;
    notifyListeners();
  }

  /// Mark a persistent row for DELETE. Cell edits on that row are dropped
  /// — DELETE overrides UPDATE.
  void deletePersistentRow(int row) {
    final result = _result;
    if (result == null) return;
    if (row < 0 || row >= result.rows.length) return;
    _deletedRows.add(row);
    _edits.removeWhere((key, _) => key.row == row);
    notifyListeners();
  }

  void restoreDeletedRow(int row) {
    if (_deletedRows.remove(row)) notifyListeners();
  }

  void addInsert(PendingInsert insert) {
    _inserts.add(insert);
    notifyListeners();
  }

  void removeInsertAt(int insertIdx) {
    if (insertIdx < 0 || insertIdx >= _inserts.length) return;
    _inserts.removeAt(insertIdx);
    notifyListeners();
  }

  /// Snapshot of pending inserts for batch construction. Copies the list
  /// so the caller can hand it to [EditBatch] without aliasing the live
  /// view.
  List<PendingInsert> snapshotInserts() => List.of(_inserts);

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  String get title => table.name;
}
