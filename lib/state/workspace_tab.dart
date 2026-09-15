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

  bool _disposed = false;

  /// True once the tab has been closed. Every round-trip the controller
  /// starts on a tab can outlive it — a 20-second query, a DDL fetch, an
  /// EXPLAIN — and the user is free to ⌘W in the meantime. Callers that do
  /// more than notify should check this and drop the result.
  bool get disposed => _disposed;

  /// Swallowed after [dispose]. `ChangeNotifier` asserts on a notification
  /// to a disposed instance, so without this a query landing after its tab
  /// closed throws out of the controller — visible in a debug build as a
  /// sticky "Unexpected error" toast, and a write to a dead notifier in
  /// release.
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

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
  QueryTab(super.id, {String name = 'Query', this.sql = ''}) : _name = name;

  // ignore_for_file: prefer_initializing_formals
  String _name;
  QueryResult? _result;
  bool _running = false;
  String? _runningSql;
  bool _cancelRequested = false;
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

  /// The editor's live text. A plain field, deliberately NOT notifying.
  ///
  /// Every writer is the query editor recording the text of its own
  /// `CodeEditorController`, which needs no telling. Notifying fanned a
  /// single keystroke out to three un-gated listeners: the editor subtree
  /// rebuilt twice (its own `setState` plus the tab listener), the plan
  /// view re-parsed and re-analysed the whole plan, and `TabsController`
  /// forwarded it to the sidebar, which re-derived the favourites and
  /// frequent lists and re-allocated a row widget for every table in
  /// every expanded schema. On a long script against a large catalog that
  /// was enough for typing to lag behind the caret.
  ///
  /// A future writer that isn't the editor should notify explicitly.
  String sql;

  QueryResult? get result => _result;

  /// Wall-clock time the most recent run completed. Powers the "refreshed
  /// HH:MM:SS" stamp in the query pagebar.
  DateTime? get lastRefreshedAt => _lastRefreshedAt;

  /// SQL the most recent run actually sent — may differ from [sql] when the
  /// user invoked Run statement on a single block. The footer's refresh
  /// button re-issues this exact text rather than the whole editor body.
  String? get lastRunSql => _lastRunSql;

  bool get running => _running;

  /// Exact SQL currently in flight, or null when idle. The query editor
  /// reads this to decide which gutter row shows the stop square — a
  /// run-all loop updates it before each statement so the indicator
  /// hops down through the script as the loop advances.
  String? get runningSql => _runningSql;

  /// True after [requestCancel]; the run-all loop reads it between
  /// statements to break early. Cleared on the next [beginRun].
  bool get cancelRequested => _cancelRequested;

  /// Active section below the editor.
  QueryResultsView get view => _view;

  void setView(QueryResultsView value) {
    if (_view == value) return;
    _view = value;
    notifyListeners();
  }

  /// Mark a query as in-flight. Pairs with [completeRun]. [sql] records
  /// the exact statement being sent so the editor's gutter can swap the
  /// matching line's play icon for a stop square.
  void beginRun({String? sql}) {
    if (_running) return;
    _running = true;
    _runningSql = sql;
    _cancelRequested = false;
    notifyListeners();
  }

  /// Flip the cancel flag. The runner reads it between statements and
  /// the editor uses it to render the stop square in a pressed state.
  /// Actual in-flight cancellation (Postgres only) is the caller's job.
  void requestCancel() {
    if (!_running || _cancelRequested) return;
    _cancelRequested = true;
    notifyListeners();
  }

  /// Atomic post-run swap: result, lastRunSql, lastRefreshedAt, plan-cache
  /// invalidation, and message-log append land in one notification so any
  /// listener sees a consistent post-run snapshot.
  void completeRun({
    required QueryResult result,
    required String sql,
    required QueryMessage message,
    required int maxMessages,
  }) {
    _result = result;
    _lastRunSql = sql;
    _lastRefreshedAt = DateTime.now();
    if (_planSourceSql != sql) {
      _planJson = null;
      _planError = null;
      _planLoading = false;
      _planSourceSql = null;
    }
    _messages.add(message);
    if (_messages.length > maxMessages) {
      _messages.removeRange(0, _messages.length - maxMessages);
    }
    _running = false;
    _runningSql = null;
    notifyListeners();
  }

  Map<String, dynamic>? get planJson => _planJson;

  String? get planError => _planError;

  bool get planLoading => _planLoading;

  /// SQL the cached plan was computed against. Stays in sync with
  /// [lastRunSql] until the next run, at which point the plan view shows
  /// a stale indicator unless [loadQueryPlan] is invoked again.
  String? get planSourceSql => _planSourceSql;

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

  String? get error => _error;

  bool get loading => _loading;

  /// Mark a DDL fetch as in-flight. Clears the previous error so a retry
  /// after a transient failure doesn't show stale red text alongside a
  /// fresh spinner.
  void beginDdlLoad() {
    _loading = true;
    _error = null;
    notifyListeners();
  }

  void completeDdlLoad(String ddl) {
    _ddl = ddl;
    _error = null;
    _loading = false;
    notifyListeners();
  }

  void failDdlLoad(Object error) {
    _error = error.toString();
    _loading = false;
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

  /// Generation token for in-flight page loads. Each call to [beginPageLoad]
  /// bumps this; [completePageLoad] / [failPageLoad] only apply when the
  /// caller's token still matches. Without the CAS, a slow first request
  /// can land its result after a faster second request and pair stale rows
  /// with the live clauses on screen.
  int _loadGeneration = 0;

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

  bool get loading => _loading;

  bool get applying => _applying;

  int get page => _page;

  int get pageSize => _pageSize;

  set pageSize(int value) {
    if (_pageSize == value) return;
    _pageSize = value;
    notifyListeners();
  }

  int get totalRows => _totalRows;

  /// Apply a fresh row-count if [filterAtRequest] still matches the live
  /// filter. A slow count can outlive the filter that triggered it; the
  /// match check keeps a stale total from overwriting a fresher one.
  void setTotalRows(int value, {required String filterAtRequest}) {
    if (_filter != filterAtRequest) return;
    if (_totalRows == value) return;
    _totalRows = value;
    notifyListeners();
  }

  /// Column projection — a raw SQL select list. Defaults to `*`.
  String get selectList => _selectList;

  /// Active row filter — a raw SQL `WHERE` fragment typed by the user.
  String get filter => _filter;

  /// Active sort — a raw SQL `ORDER BY` fragment, also driven by header clicks.
  String get orderBy => _orderBy;

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

  /// Begin a page fetch against [page]. Eagerly bumps the page index so the
  /// pagebar shows the new number immediately; returns a generation token
  /// the caller must pass back to [completePageLoad] / [failPageLoad].
  /// Concurrent loads are tracked by token — late arrivals from a
  /// superseded fetch are rejected and don't desync clauses from rows.
  ///
  /// Both [edits] and [deletedRows] address rows by their index into
  /// `result.rows`, so a fetch that replaces those rows invalidates every
  /// one of them. They are dropped together: a surviving delete index would
  /// resolve against the *new* page's `rowIds` on the next Apply and remove
  /// whatever row now occupies that slot, and the repository's
  /// `affectedRows == 1` guard cannot catch it because that row does exist.
  /// Pending inserts survive — they carry column names and values, not row
  /// positions, and `buildSlots` re-anchors an out-of-range `afterRow`.
  int beginPageLoad({required int page}) {
    _loadGeneration++;
    _loading = true;
    _page = page;
    _edits.clear();
    _deletedRows.clear();
    notifyListeners();
    return _loadGeneration;
  }

  /// Atomic post-fetch swap: pairs the new clauses with the new result so
  /// the clausebar never displays clauses that don't describe the rows on
  /// screen. Ignored if [token] is stale (a newer fetch has since started).
  bool completePageLoad(
    int token, {
    required QueryResult result,
    String? filter,
    String? selectList,
    String? orderBy,
  }) {
    if (token != _loadGeneration) return false;
    _result = result;
    if (filter != null) _filter = filter;
    if (selectList != null) _selectList = selectList;
    if (orderBy != null) _orderBy = orderBy;
    _lastRefreshedAt = DateTime.now();
    _loading = false;
    notifyListeners();
    return true;
  }

  /// Failure counterpart to [completePageLoad]: leaves clauses untouched
  /// (so the bar keeps matching the previous rows) and surfaces the error
  /// as a failed [QueryResult]. Ignored if [token] is stale.
  bool failPageLoad(int token, Object error) {
    if (token != _loadGeneration) return false;
    _result = QueryResult.failure(
      error: error.toString(),
      elapsed: Duration.zero,
    );
    _loading = false;
    notifyListeners();
    return true;
  }

  /// Mark an apply-edits round-trip as in-flight. Pairs with [endApply].
  void beginApply() {
    if (_applying) return;
    _applying = true;
    notifyListeners();
  }

  void endApply() {
    if (!_applying) return;
    _applying = false;
    notifyListeners();
  }

  /// Filter mutator — clausebar autocomplete and the navigation history
  /// snapshot apply step both land here.
  void setFilter(String value) {
    if (_filter == value) return;
    _filter = value;
    notifyListeners();
  }

  void setSelectList(String value) {
    if (_selectList == value) return;
    _selectList = value;
    notifyListeners();
  }

  void setOrderBy(String value) {
    if (_orderBy == value) return;
    _orderBy = value;
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
