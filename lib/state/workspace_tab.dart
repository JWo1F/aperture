import 'package:flutter/foundation.dart';

import '../models/cell_edit.dart';
import '../models/db_object.dart';
import '../models/query_message.dart';
import '../models/query_result.dart';

export '../models/cell_edit.dart'
    show CellEdit, CellEditValue, CellLiteral, CellDefault, PendingInsert, EditBatch;
export '../models/query_message.dart';

/// A tab in the centre workspace. Either a free-form SQL editor, a data
/// view bound to one relation, or a schema viewer.
///
/// Each tab is its own [ChangeNotifier] so a widget tree scoped to one
/// tab can rebuild on its own data without dragging in unrelated state.
/// Callers that mutate tab fields go through the setters below, which
/// notify on change; mutations to internal collections (the cell-edit
/// map, the column-widths map) are followed by an explicit
/// [markChanged] call from the [TabsController] mutator.
sealed class WorkspaceTab extends ChangeNotifier {
  WorkspaceTab(this.id);

  final String id;

  /// Per-tab column widths, keyed by column name. Persisted for the tab's
  /// lifetime so resizes survive pagination, filters, sorts, and tab switches.
  final Map<String, double> columnWidths = {};

  String get title;

  /// Notify all listeners that something on this tab changed. Internal
  /// to the state layer — UI code never calls this directly.
  void markChanged() => notifyListeners();
}

/// Which section of the query tab the user is currently viewing below
/// the editor: the result grid, the plan tree, or the messages log.
enum QueryResultsView { results, plan, messages }

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
  QueryResultsView _view = QueryResultsView.results;

  /// Plan-tab state. [planJson] is the top-level node of the parsed JSON
  /// EXPLAIN output. [planError] holds a server-side error if EXPLAIN
  /// failed. [planLoading] flips while the EXPLAIN round-trip is in flight.
  Map<String, dynamic>? _planJson;
  String? _planError;
  bool _planLoading = false;
  String? _planSourceSql;

  /// Per-tab message log — every SQL this tab issued, newest last.
  final List<QueryMessage> messages = [];

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

  /// Auto-refresh cadence for this query tab. The timer in [TabsController]
  /// re-runs [lastRunSql] on every tick; `null` means manual.
  Duration? get autoRefreshInterval => _autoRefreshInterval;

  set autoRefreshInterval(Duration? value) {
    if (_autoRefreshInterval == value) return;
    _autoRefreshInterval = value;
    notifyListeners();
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
  DateTime? _lastRefreshedAt;

  /// Pending, un-applied cell edits, keyed by (row, column). Only meaningful
  /// for persistent rows — pending inserts mutate [inserts] directly.
  final Map<CellEdit, CellEditValue> edits = {};

  /// Row indexes (into [result.rows]) marked for DELETE on Apply. Cell
  /// edits on a deleted row are dropped — DELETE supersedes UPDATE.
  final Set<int> deletedRows = {};

  /// Synthetic rows queued for INSERT. The grid renders them after the
  /// persistent rows so the user can edit their cells inline before Apply.
  final List<PendingInsert> inserts = [];

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

  /// When set, [TabsController] periodically re-fetches the current page on
  /// this interval. The Timer itself lives on the tab; [TabsController.dispose]
  /// makes sure it shuts down when the connection drops.
  Duration? get autoRefreshInterval => _autoRefreshInterval;

  set autoRefreshInterval(Duration? value) {
    _autoRefreshInterval = value;
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
      edits.isNotEmpty || deletedRows.isNotEmpty || inserts.isNotEmpty;

  /// Aggregate count of pending operations (cell edits + row deletes + row
  /// inserts) shown in the pending-edits chip.
  int get pendingOpCount =>
      edits.length + deletedRows.length + inserts.length;

  int get pageCount =>
      _totalRows == 0 ? 1 : ((_totalRows - 1) ~/ _pageSize) + 1;

  int get offset => _page * _pageSize;

  @override
  String get title => table.name;
}
