import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/count_format.dart';
import '../../models/db_object.dart';
import '../../models/query_result.dart';
import '../../services/sql_complete.dart';
import '../../services/sql_statements.dart';
import '../../state/app_state.dart';
import '../../state/app_store.dart';
import '../../state/catalog_controller.dart';
import '../../state/tabs_controller.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../widgets/code_editor.dart';
import '../widgets/common.dart';
import '../widgets/pagebar.dart';
import '../widgets/resize_handle.dart';
import 'query_messages_view.dart';
import 'query_plan/view/query_plan_view.dart';
import 'results_grid/results_grid.dart';

/// Syntax-highlighted SQL editor over the result grid.
///
/// - Autosaves the text to the active connection's SavedQuery list (400ms
///   debounce) so queries survive restarts.
/// - Parses statements as you type; the gutter shows a ▶ icon next to each
///   statement's first line, click to run just that block.
/// - ⌘↵ runs the statement under the cursor; ⌘⇧↵ runs every statement.
class QueryEditor extends StatefulWidget {
  const QueryEditor({super.key, required this.tab});

  final QueryTab tab;

  @override
  State<QueryEditor> createState() => _QueryEditorState();
}

class _QueryEditorState extends State<QueryEditor> {
  late final CodeEditorController _controller;
  final FocusNode _focusNode = FocusNode();
  Timer? _saveTimer;
  List<SqlStatement> _statements = const [];
  int? _cursorStmt; // 1-based statement index containing the caret

  @override
  void initState() {
    super.initState();
    _controller = CodeEditorController(text: widget.tab.sql);
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
        context
            .read<TabsController>()
            .updateQuerySql(widget.tab, _controller.text);
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

  int? _computeCursorStmt() {
    final offset = _controller.selection.baseOffset;
    if (offset < 0 || _statements.isEmpty) return null;
    for (var i = 0; i < _statements.length; i++) {
      final s = _statements[i];
      if (offset >= s.startOffset && offset <= s.endOffset) return i + 1;
    }
    return null;
  }

  Future<void> _runAll() async {
    widget.tab.sql = _controller.text;
    widget.tab.setView(QueryResultsView.results);
    final tabs = context.read<TabsController>();
    final stmts = _statements.isNotEmpty
        ? _statements
        : parseSqlStatements(_controller.text);

    if (stmts.length <= 1) {
      await tabs.runQuery(widget.tab);
      return;
    }

    // The postgres extended query protocol doesn't allow multiple commands in
    // one prepared statement. Send each statement separately and surface the
    // last result; stop on the first failure so the user sees the error.
    for (final s in stmts) {
      await tabs.runQuery(widget.tab, sqlOverride: s.text);
      if (widget.tab.result?.isError ?? false) break;
    }
  }

  void _runStatement(SqlStatement stmt) {
    widget.tab.setView(QueryResultsView.results);
    context.read<TabsController>().runQuery(widget.tab, sqlOverride: stmt.text);
  }

  void _runAtCursor() {
    if (_statements.isEmpty) return;
    final offset = _controller.selection.baseOffset;
    final stmt = offset < 0
        ? _statements.first
        : statementAtOffset(_statements, offset) ?? _statements.last;
    _runStatement(stmt);
  }

  /// Picks the content widget for the current [QueryTab.view] selection.
  /// Each section is responsible for its own empty-state copy so the
  /// switch reads as a flat dispatch table.
  Widget _buildContent(
    AppState appState,
    CatalogController catalog,
    QueryTab tab,
  ) {
    switch (tab.view) {
      case QueryResultsView.results:
        if (tab.result == null) {
          return const EmptyState(
            icon: Icons.terminal,
            title: 'Run a query',
            message:
                'Write SQL above and press ⌘↵ (or click ▶ in the gutter '
                'for a single statement).',
          );
        }
        return ResultsGrid(
          result: tab.result!,
          widths: tab.columnWidths,
          foreignKeys: _resolveFks(catalog, tab.result!),
          onFollowForeignKey: (fk, value) =>
              appState.followForeignKey(fk, value),
          findRowOwner: (col) => _findRowOwner(catalog, tab.result!, col),
          onFindRow: (table, col, value) =>
              appState.findRowInTable(table, col, value),
        );
      case QueryResultsView.plan:
        return QueryPlanView(tab: tab);
      case QueryResultsView.messages:
        return QueryMessagesView(tab: tab);
    }
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

  @override
  Widget build(BuildContext context) {
    // Read controllers non-reactively. The State already listens to the tab
    // directly (see initState → addListener(_onTabChange)) which triggers
    // setState, so tab field updates rebuild this widget without going
    // through any controller's notifications. The one slice of app-wide
    // state we still need to react to is the editor/results split — pulled
    // narrowly so a sidebar drag doesn't reach this widget.
    final appState = context.read<AppState>();
    final catalog = context.read<CatalogController>();
    final store = context.read<AppStore>();
    final fraction = context.select<AppStore, double>(
      (s) => s.queryResultsFraction,
    );
    final tab = widget.tab;

    final activeStmt =
        _cursorStmt != null &&
            _cursorStmt! >= 1 &&
            _cursorStmt! <= _statements.length
        ? _statements[_cursorStmt! - 1]
        : null;
    final bands = <LineBand>[
      if (activeStmt != null)
        LineBand(
          startLine: activeStmt.startLine,
          endLine:
              activeStmt.startLine + '\n'.allMatches(activeStmt.text).length,
          color: AppColors.accent.withValues(alpha: 0.06),
        ),
    ];

    final stmtByLine = <int, SqlStatement>{
      for (final s in _statements) s.startLine: s,
    };

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
      child: CodeEditor(
        controller: _controller,
        focusNode: _focusNode,
        showLineNumbers: true,
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.md,
          vertical: 12,
        ),
        lineBands: bands,
        lineIcon: (line) {
          final stmt = stmtByLine[line];
          if (stmt == null) return null;
          return LineIcon(
            icon: Icon(
              Icons.play_arrow_rounded,
              size: 14,
              color: AppColors.success,
            ),
            tooltip: 'Run statement (⌘⇧↵)',
            onTap: () => _runStatement(stmt),
          );
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
        _Toolbar(
          tab: tab,
          onRunStatement: tab.running || _statements.isEmpty
              ? null
              : _runAtCursor,
          onRunAll: tab.running ? null : _runAll,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Reserve space for the fixed-height tab strip + the drag
              // handle above it; the fraction governs the *split-able*
              // remainder so neither chrome row steals height from either
              // side.
              const dividerHeight = 24.0;
              const handleHeight = 6.0;
              const minSide = 80.0;
              final available =
                  (constraints.maxHeight - dividerHeight - handleHeight).clamp(
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
                  _QuerySplitHandle(
                    store: store,
                    available: available,
                    handleHeight: handleHeight,
                  ),
                  _ResultsDivider(tab: tab),
                  SizedBox(
                    height: resultsHeight,
                    child: ClipRect(
                      child: Container(
                        color: AppColors.bg,
                        child: _buildContent(appState, catalog, tab),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        _QueryPagebar(tab: tab),
      ],
    );
  }
}

/// Drag handle between the editor and the results pane. Captures the
/// starting fraction (and the available height at that instant) on drag
/// start so the new fraction is computed against fixed anchors — without
/// this, dragging past the clamp lets cumulative motion silently "bank"
/// and the pane jumps back on direction reversal.
class _QuerySplitHandle extends StatefulWidget {
  const _QuerySplitHandle({
    required this.store,
    required this.available,
    required this.handleHeight,
  });

  final AppStore store;
  final double available;
  final double handleHeight;

  @override
  State<_QuerySplitHandle> createState() => _QuerySplitHandleState();
}

class _QuerySplitHandleState extends State<_QuerySplitHandle> {
  double _startFraction = 0;
  double _startAvailable = 0;

  @override
  Widget build(BuildContext context) {
    return ResizeHandle(
      axis: Axis.horizontal,
      thickness: widget.handleHeight,
      onDragStart: () {
        _startFraction = widget.store.queryResultsFraction;
        _startAvailable = widget.available;
      },
      onDragUpdate: (dy) {
        if (_startAvailable <= 0) return;
        widget.store.setQueryResultsFraction(
          _startFraction - dy / _startAvailable,
        );
      },
    );
  }
}

/// Query editor toolbar — matches the design's two-action primary cluster
/// (Run statement / Run all) with inline kbd chips, an Export action, and a
/// scratch/save status breadcrumb on the right.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.tab,
    required this.onRunStatement,
    required this.onRunAll,
  });

  final QueryTab tab;
  final VoidCallback? onRunStatement;
  final VoidCallback? onRunAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _QtPrimaryButton(
            label: tab.running ? 'Running…' : 'Run statement',
            icon: Icons.play_arrow,
            kbd: const ['⌘', '↵'],
            onPressed: onRunStatement,
          ),
          const SizedBox(width: 4),
          _QtBorderButton(
            label: 'Run all',
            icon: Icons.bolt_outlined,
            kbd: const ['⌘', '⇧', '↵'],
            onPressed: onRunAll,
          ),
        ],
      ),
    );
  }
}

/// Filled-accent button used as the primary "Run" in the query toolbar.
class _QtPrimaryButton extends StatelessWidget {
  const _QtPrimaryButton({
    required this.label,
    required this.icon,
    required this.kbd,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final List<String> kbd;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Hoverable(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onTap: onPressed,
      builder: (context, hovering) {
        final bg = !enabled
            ? AppColors.accent.withValues(alpha: 0.4)
            : (hovering ? AppColors.accentHover : AppColors.accent);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: 24,
          padding: const EdgeInsets.only(left: 9, right: 6),
          decoration: BoxDecoration(color: bg, borderRadius: Radii.brSm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                label,
                style: AppTheme.ui(
                  size: 11.5,
                  color: Colors.white,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 7),
              _QtInlineKbd(parts: kbd, onAccent: true),
            ],
          ),
        );
      },
    );
  }
}

/// Outline ghost button with optional kbd cluster.
class _QtBorderButton extends StatelessWidget {
  const _QtBorderButton({
    required this.label,
    required this.icon,
    this.kbd,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final List<String>? kbd;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Hoverable(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onTap: onPressed,
      builder: (context, hovering) {
        final fg = enabled
            ? (hovering ? AppColors.textPrimary : AppColors.textSecondary)
            : AppColors.textMuted.withValues(alpha: 0.5);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: 24,
          padding: const EdgeInsets.only(left: 9, right: 6),
          decoration: BoxDecoration(
            color: hovering && enabled
                ? AppColors.surfaceHover
                : AppColors.surfaceHover.withValues(alpha: 0),
            borderRadius: Radii.brSm,
            border: Border.all(
              color: hovering && enabled
                  ? AppColors.borderStrong
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: fg),
              const SizedBox(width: 5),
              Text(
                label,
                style: AppTheme.ui(
                  size: 11.5,
                  color: fg,
                  weight: FontWeight.w500,
                ),
              ),
              if (kbd != null) ...[
                const SizedBox(width: 7),
                _QtInlineKbd(parts: kbd!),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Tiny mono kbd chip group; the `onAccent` variant uses a translucent white
/// chip so it reads correctly on the primary button background.
class _QtInlineKbd extends StatelessWidget {
  const _QtInlineKbd({required this.parts, this.onAccent = false});

  final List<String> parts;
  final bool onAccent;

  @override
  Widget build(BuildContext context) {
    final double dim = onAccent ? 15 : 16;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Container(
            height: dim,
            constraints: BoxConstraints(minWidth: dim),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: onAccent
                  ? Colors.white.withValues(alpha: 0.16)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(4),
              border: onAccent ? null : Border.all(color: AppColors.border),
            ),
            child: Text(
              parts[i],
              textAlign: TextAlign.center,
              // height: 1.0 collapses the mono font's 1.4 line box so the
              // glyph sits centred instead of riding the cap's top edge.
              style: AppTheme.mono(
                size: onAccent ? 9.5 : 10,
                color: onAccent
                    ? Colors.white.withValues(alpha: 0.92)
                    : AppColors.textMuted,
                weight: FontWeight.w500,
              ).copyWith(height: 1.0),
            ),
          ),
        ],
      ],
    );
  }
}

/// Tab strip above the results pane: Results / Plan / Messages. The
/// active section's content area swaps below; numeric readouts live in
/// the footer pagebar so they don't double up here.
class _ResultsDivider extends StatelessWidget {
  const _ResultsDivider({required this.tab});

  final QueryTab tab;

  @override
  Widget build(BuildContext context) {
    final messageCount = tab.messages.length;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          _RdTab(
            label: 'Results',
            active: tab.view == QueryResultsView.results,
            onTap: () => tab.setView(QueryResultsView.results),
          ),
          const SizedBox(width: 12),
          _RdTab(
            label: 'Plan',
            active: tab.view == QueryResultsView.plan,
            onTap: () => tab.setView(QueryResultsView.plan),
          ),
          const SizedBox(width: 12),
          _RdTab(
            label: 'Messages',
            active: tab.view == QueryResultsView.messages,
            onTap: () => tab.setView(QueryResultsView.messages),
            badge: messageCount == 0 ? null : '$messageCount',
          ),
        ],
      ),
    );
  }
}

class _RdTab extends StatelessWidget {
  const _RdTab({
    required this.label,
    required this.active,
    required this.onTap,
    this.badge,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      cursor: SystemMouseCursors.click,
      onTap: onTap,
      builder: (context, hovering) => Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: AppTheme.mono(
                    size: 10.5,
                    color: active
                        ? AppColors.textPrimary
                        : (hovering
                              ? AppColors.textSecondary
                              : AppColors.textMuted),
                    weight: FontWeight.w600,
                  ).copyWith(letterSpacing: 0.04 * 10.5),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    badge!,
                    style: AppTheme.mono(
                      size: 10,
                      color: active ? AppColors.accent : AppColors.textMuted,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (active)
            Positioned(
              left: 0,
              right: 0,
              bottom: -5,
              child: Container(height: 1, color: AppColors.accent),
            ),
        ],
      ),
    );
  }
}

/// Builds a column-name → FK lookup for a raw query result. Prefers the
/// source-relation OID exposed by the wire protocol so the FK action targets
/// the *actual* table the column came from; falls back to the catalog-wide
/// aggregation when the column is an expression (no source relation).
Map<String, DbForeignKey> _resolveFks(
  CatalogController catalog,
  QueryResult result,
) {
  final schemas = result.columnSchemas;
  if (schemas == null) return catalog.aggregatedForeignKeys;
  final out = <String, DbForeignKey>{};
  for (final schema in schemas) {
    final precise = catalog.findForeignKey(schema.tableOid, schema.name);
    if (precise != null) {
      out[schema.name] = precise;
    } else if (!schema.hasSourceRelation) {
      final guess = catalog.aggregatedForeignKeys[schema.name];
      if (guess != null) out[schema.name] = guess;
    }
  }
  return out;
}

/// Returns the relation whose PK is [columnName], preferring the source
/// relation OID from the wire protocol when present. Falls back to the
/// ambiguity-safe catalog lookup otherwise.
DbTable? _findRowOwner(
  CatalogController catalog,
  QueryResult result,
  String columnName,
) {
  final schemas = result.columnSchemas;
  if (schemas == null) return catalog.findPrimaryKeyOwner(columnName);
  for (final schema in schemas) {
    if (schema.name != columnName) continue;
    return catalog.findPrimaryKeyOwnerByOid(schema.tableOid, columnName);
  }
  return catalog.findPrimaryKeyOwner(columnName);
}

/// Bottom status strip for a query tab — mirrors the table view's pagebar
/// shape (28px, hairline top, bgDeep) but trades pagination chevrons and
/// auto-refresh for the static run-summary a query produces: rows or
/// affected count, elapsed ms, truncation flag, "refreshed HH:MM:SS", and
/// a success/error indicator on the right.
class _QueryPagebar extends StatelessWidget {
  const _QueryPagebar({required this.tab});

  final QueryTab tab;

  @override
  Widget build(BuildContext context) {
    // _QueryPagebar reads only from `tab` and dispatches to TabsController;
    // it lives inside a per-tab ListenableBuilder, so a plain context.read
    // is enough — no need to subscribe to the controller.
    final tabs = context.read<TabsController>();
    final result = tab.result;
    final refreshedAt = tab.lastRefreshedAt;
    final lastRunSql = tab.lastRunSql;
    final canRefresh = !tab.running && lastRunSql != null;

    return Container(
      height: pagebarHeight,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (result == null)
            PbStat(head: tab.running ? 'running…' : 'idle')
          else ...[
            if (result.hasColumns)
              PbStat(
                head: withCommas(result.rows.length),
                tail: ' rows',
                headHighlight: true,
              )
            else if (result.affectedRows != null)
              PbStat(
                head: withCommas(result.affectedRows!),
                tail: ' affected',
                headHighlight: true,
              )
            else
              const PbStat(head: 'done'),
            const PbDot(),
            PbStat(head: '${result.elapsed.inMilliseconds}', tail: 'ms'),
            if (result.truncatedAt != null) ...[
              const PbDot(),
              PbStat(
                head: 'truncated at ',
                mid: withCommas(result.truncatedAt!),
              ),
            ],
          ],
          if (refreshedAt != null) ...[
            const PbDot(),
            PbStat(head: 'refreshed ', mid: formatPagebarClock(refreshedAt)),
          ],
          const Spacer(),
          if (result != null) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: result.isError ? AppColors.error : AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  result.isError ? 'error' : 'success',
                  style: AppTheme.mono(
                    size: 10.5,
                    color: result.isError ? AppColors.error : AppColors.success,
                  ),
                ),
              ],
            ),
            const PbDot(),
          ],
          RefreshDropdown(
            interval: tab.autoRefreshInterval,
            busy: tab.running,
            canRefresh: canRefresh,
            onManualRefresh: () => tabs.runQuery(tab, sqlOverride: lastRunSql),
            onSetInterval: (d) => tabs.setQueryAutoRefresh(tab, d),
          ),
        ],
      ),
    );
  }
}
