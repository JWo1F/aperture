import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../../../services/sql_complete.dart';
import '../../../services/sql_statements.dart';
import '../../../state/app_globals.dart';
import '../../../state/catalog_controller.dart';
import '../../../state/workspace_tab.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import '../../widgets/common.dart';
import '../../widgets/value_selector.dart';
import '../query_messages_view.dart';
import '../query_plan/view/query_plan_view.dart';
import '../results_grid/results_grid.dart';
import 'query_fk.dart';
import 'query_split_handle.dart';
import 'query_statusbar.dart';
import 'query_toolbar.dart';
import 'sql_autocomplete.dart';
import 'sql_editor.dart';
import 'results_tab_strip.dart';

/// The query page: toolbar, SQL editor, section strip, results, status bar.
///
/// This widget owns run orchestration and the caret-derived statement
/// model; everything that paints lives in a sibling module. The editor
/// autosaves to the connection's SavedQuery list on a 400 ms debounce, so
/// a script survives a restart without an explicit save.
///
/// ⌘↵ runs the statement under the caret; ⌘⇧↵ runs every statement in
/// sequence; the gutter ▶ runs one block directly.
class QueryEditor extends StatefulWidget {
  const QueryEditor({super.key, required this.tab});

  final QueryTab tab;

  @override
  State<QueryEditor> createState() => _QueryEditorState();
}

class _QueryEditorState extends State<QueryEditor> {
  late final CodeLineEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  Timer? _saveTimer;
  List<SqlStatement> _statements = const [];
  int? _cursorStmt; // 1-based statement index containing the caret

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController.fromText(widget.tab.sql);
    _controller.addListener(_onControllerChange);
    // Per-tab fields (view, plan*, messages, lastRunSql, …) notify the
    // tab directly. The TabsController only fires for things that mutate
    // the tab list; without this listener, clicking a section tab would
    // update `tab.view` but the editor wouldn't rebuild until the next
    // unrelated AppState change.
    widget.tab.addListener(_onTabChange);
    _recomputeStatements();
    _recomputeCursorStmt();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _controller.removeListener(_onControllerChange);
    _controller.dispose();
    widget.tab.removeListener(_onTabChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onTabChange() {
    if (mounted) setState(() {});
  }

  void _onControllerChange() {
    final text = _controller.text;
    var dirty = false;

    if (widget.tab.sql != text) {
      widget.tab.sql = text;
      _recomputeStatements();
      dirty = true;

      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        appState.tabsController.updateQuerySql(widget.tab, _controller.text);
      });
    }

    final nextCursor = _computeCursorStmt();
    if (nextCursor != _cursorStmt) {
      _cursorStmt = nextCursor;
      dirty = true;
    }

    if (dirty) setState(() {});
  }

  void _recomputeStatements() {
    _statements = parseSqlStatements(_controller.text);
  }

  void _recomputeCursorStmt() {
    _cursorStmt = _computeCursorStmt();
  }

  /// The caret as an offset into the whole script, where the statement
  /// model lives.
  int get _caret =>
      flatOffset(_controller.codeLines, _controller.selection.base);

  int? _computeCursorStmt() {
    final offset = _caret;
    if (offset < 0 || _statements.isEmpty) return null;
    for (var i = 0; i < _statements.length; i++) {
      final s = _statements[i];
      if (offset >= s.startOffset && offset <= s.endOffset) return i + 1;
    }
    return null;
  }

  /// 1-based position of the statement currently in flight, or null.
  ///
  /// The Run-all loop sets `runningSql` to each statement's exact text, so
  /// a match identifies the block. A single-statement script is the one
  /// case that sends `tab.sql` whole — it can only be statement one, so
  /// resolve it positionally rather than leaving the indicator dark.
  int? get _runningStmt {
    final sql = widget.tab.runningSql;
    if (sql == null) return null;
    for (var i = 0; i < _statements.length; i++) {
      if (_statements[i].text == sql) return i + 1;
    }
    return _statements.length == 1 ? 1 : null;
  }

  SqlStatement? _statementAt(int? oneBased) {
    if (oneBased == null) return null;
    if (oneBased < 1 || oneBased > _statements.length) return null;
    return _statements[oneBased - 1];
  }

  Future<void> _runAll() async {
    widget.tab.sql = _controller.text;
    widget.tab.setView(QueryResultsView.results);
    final tabs = appState.tabsController;
    final stmts = _statements.isNotEmpty
        ? _statements
        : parseSqlStatements(_controller.text);

    if (stmts.length <= 1) {
      await tabs.runQuery(widget.tab);
      return;
    }

    // The postgres extended query protocol doesn't allow multiple commands in
    // one prepared statement. Send each statement separately and surface the
    // last result; stop on the first failure (or a user-requested cancel) so
    // the user sees the error or stops the chain.
    for (final s in stmts) {
      await tabs.runQuery(widget.tab, sqlOverride: s.text);
      if (widget.tab.result?.isError ?? false) break;
      if (widget.tab.cancelRequested) break;
    }
  }

  void _runStatement(SqlStatement stmt) {
    widget.tab.setView(QueryResultsView.results);
    appState.tabsController.runQuery(widget.tab, sqlOverride: stmt.text);
  }

  void _runAtCursor() {
    if (_statements.isEmpty) return;
    final offset = _caret;
    final stmt = offset < 0
        ? _statements.first
        : statementAtOffset(_statements, offset) ?? _statements.last;
    _runStatement(stmt);
  }

  void _cancelRunning() {
    widget.tab.requestCancel();
    appState.session.service?.cancelCurrent();
  }

  void _explain() {
    final tab = widget.tab;
    tab.setView(QueryResultsView.plan);
    // A cached plan that still describes the current result is the answer
    // — re-issuing EXPLAIN would run the statement a second time for real,
    // since read queries are planned with ANALYZE.
    if (tab.planJson != null && tab.planSourceSql == tab.lastRunSql) return;
    appState.tabsController.loadQueryPlan(tab);
  }

  /// Picks the content widget for the current [QueryTab.view] selection.
  /// Each section is responsible for its own empty-state copy so the
  /// switch reads as a flat dispatch table.
  Widget _buildContent(CatalogController catalog, QueryTab tab) {
    switch (tab.view) {
      case QueryResultsView.results:
        if (tab.result == null) {
          return const EmptyState(
            icon: Hgi.terminal,
            title: 'Run a query',
            message:
                'Write SQL above and press ⌘↵ to run the statement under '
                'the caret, or click ▶ in the gutter to run one block.',
          );
        }
        return ResultsGrid(
          result: tab.result!,
          widths: tab.columnWidths,
          // A query tab has no table key to persist against, so the tab's
          // own map is the whole story — without writing back, every
          // re-run re-derived auto widths and undid the user's drag.
          onWidthChanged: tab.setColumnWidth,
          foreignKeys: resolveResultForeignKeys(catalog, tab.result!),
          onFollowForeignKey: (fk, value) =>
              appState.followForeignKey(fk, value),
          findRowOwner: (col) => findResultRowOwner(catalog, tab.result!, col),
          onFindRow: (table, col, value) =>
              appState.findRowInTable(table, col, value),
        );
      case QueryResultsView.plan:
        return QueryPlanView(tab: tab);
      case QueryResultsView.messages:
        return QueryMessagesView(tab: tab);
    }
  }

  /// Highlight bands for the editor body.
  ///
  /// The in-flight statement outranks the caret's: during Run-all the two
  /// diverge as the loop walks down the script, and knowing which block is
  /// executing right now matters more than knowing where the caret rests.
  List<LineBand> _buildBands() {
    final running = _statementAt(_runningStmt);
    final active = _statementAt(_cursorStmt);

    LineBand band(SqlStatement s, Color tint, Color spine) => LineBand(
      startLine: s.startLine,
      endLine: s.startLine + '\n'.allMatches(s.text).length,
      color: tint,
      spine: spine,
    );

    return [
      if (running != null)
        band(
          running,
          AppColors.warn.withValues(alpha: 0.09),
          AppColors.warn.withValues(alpha: 0.75),
        ),
      if (active != null && active != running)
        band(
          active,
          AppColors.accent.withValues(alpha: 0.06),
          AppColors.accent.withValues(alpha: 0.55),
        ),
    ];
  }

  GutterAction _gutterIcon(SqlStatement stmt) {
    final tab = widget.tab;
    final isRunning = tab.running && _statementAt(_runningStmt) == stmt;
    if (isRunning) {
      return GutterAction(
        icon: Icon(Hgi.stop, size: 14, color: AppColors.error),
        tooltip: 'Cancel running statement',
        onTap: tab.cancelRequested ? null : _cancelRunning,
      );
    }
    return GutterAction(
      icon: Icon(
        Hgi.play,
        size: 14,
        color: tab.running ? AppColors.text4 : AppColors.success,
      ),
      tooltip: 'Run this statement',
      onTap: tab.running ? null : () => _runStatement(stmt),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Read controllers non-reactively. The State already listens to the tab
    // directly (see initState → addListener(_onTabChange)) which triggers
    // setState, so tab field updates rebuild this widget without going
    // through any controller's notifications. The one slice of app-wide
    // state we still need to react to is the editor/results split — pulled
    // narrowly (via Selector around the LayoutBuilder) so a sidebar drag
    // doesn't reach this widget.
    final catalog = appState.catalog;
    final store = appState.store;
    final tab = widget.tab;

    final canExplain =
        !tab.running &&
        !tab.planLoading &&
        (tab.lastRunSql ?? '').trim().isNotEmpty;

    final editor = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true):
            _runAtCursor,
        const SingleActivator(
          LogicalKeyboardKey.enter,
          meta: true,
          shift: true,
        ): _runAll,
      },
      child: SqlEditor(
        controller: _controller,
        focusNode: _focusNode,
        bands: _buildBands(),
        gutterActions: {
          for (final s in _statements) s.startLine: _gutterIcon(s),
        },
        suggest: (req) {
          // Limit scope to the statement under the cursor so a `FROM users`
          // in a sibling statement doesn't leak its columns into another one.
          final stmt = statementAtOffset(_statements, req.cursor);
          final stmtText = stmt?.text ?? req.text;
          // Resolve catalog at invocation time — the editor isn't rebuilt
          // on catalog phase-1 completion, so reading through the freshest
          // controller avoids serving stale suggestions.
          return completeQueryEditor(
            req: req,
            catalog: catalog.catalog,
            stmtText: stmtText,
            stmtStart: stmt?.startOffset ?? 0,
          );
        },
      ),
    );

    return Column(
      children: [
        QueryToolbar(
          tab: tab,
          statementIndex: _cursorStmt,
          statementCount: _statements.length,
          statementKindLabel: statementKind(
            _statementAt(_cursorStmt)?.text ?? '',
          ),
          onRunStatement: tab.running || _statements.isEmpty
              ? null
              : _runAtCursor,
          onRunAll: tab.running ? null : _runAll,
          onStop: _cancelRunning,
          onExplain: canExplain ? _explain : null,
        ),
        Expanded(
          child: Selector<double>(
            listenable: store,
            selector: () => store.queryResultsFraction,
            builder: (_, fraction) => LayoutBuilder(
              builder: (context, constraints) {
                // Reserve space for the fixed-height section strip + the
                // drag handle above it; the fraction governs the
                // *split-able* remainder so neither chrome row steals
                // height from either side.
                const stripHeight = 26.0;
                const handleHeight = 6.0;
                const minSide = 80.0;
                final available =
                    (constraints.maxHeight - stripHeight - handleHeight).clamp(
                      0.0,
                      double.infinity,
                    );
                double resultsHeight = available * fraction;
                // Enforce a per-side pixel minimum on top of the fraction
                // clamp; widgets like the empty-state card have an intrinsic
                // height that paints an overflow stripe if the pane shrinks
                // below it, and ClipRect below hides what's left over.
                if (available >= minSide * 2) {
                  resultsHeight = resultsHeight.clamp(
                    minSide,
                    available - minSide,
                  );
                }
                final editorHeight = available - resultsHeight;
                return Column(
                  children: [
                    SizedBox(
                      height: editorHeight,
                      child: ClipRect(child: editor),
                    ),
                    QuerySplitHandle(
                      available: available,
                      handleHeight: handleHeight,
                    ),
                    ResultsTabStrip(tab: tab),
                    SizedBox(
                      height: resultsHeight,
                      child: ClipRect(
                        child: Container(
                          color: AppColors.bg,
                          child: _buildContent(catalog, tab),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        QueryStatusBar(
          tab: tab,
          runningIndex: _runningStmt,
          statementCount: _statements.length,
        ),
      ],
    );
  }
}
