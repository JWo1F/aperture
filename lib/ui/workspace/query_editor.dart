import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:provider/provider.dart';

import '../../models/db_object.dart';
import '../../models/query_result.dart';
import '../../services/sql_statements.dart';
import '../../state/app_state.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../../theme/code_theme.dart';
import '../widgets/common.dart';
import '../widgets/pagebar.dart';
import '../widgets/resize_handle.dart';
import 'query_messages_view.dart';
import 'query_plan_view.dart';
import 'results_grid.dart';

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

// Editor text metrics. Body text, gutter digits, and the ▶ overlay all
// derive their Y position from these constants, so a digit at line `i`,
// the icon at line `i`, and the source character at line `i` line up
// on a single baseline.
const double _editorFontSize = 13;
const double _editorLineHeight = 1.45;
const double _editorLineBox = _editorFontSize * _editorLineHeight;

// Vertical padding we put inside the TextField's contentPadding. The
// gutter overlay applies the same value to its first line's top — that
// is the single knob that controls "how much breathing room above
// line 1". Change here, both follow.
const double _editorTopPad = 12;
const double _editorBodyLeftPad = Insets.md;

const double _gutterWidth = 56;
const double _gutterRightPad = 8;
const double _runIconColumnWidth = 18;
const double _runIconLeft = _gutterWidth - _runIconColumnWidth - 2;

// Y of the top of line `i`'s box, in Stack coordinates, after vertical
// scroll. One source of truth for digit and ▶ overlays.
double _lineTop(int i, double scrollOffset) =>
    i * _editorLineBox + _editorTopPad - scrollOffset;

class _QueryEditorState extends State<QueryEditor> {
  late final _SqlController _controller;
  late final ScrollController _bodyScroll;
  final FocusNode _focusNode = FocusNode();
  Timer? _saveTimer;
  List<SqlStatement> _statements = const [];
  int? _cursorStmt; // 1-based statement index containing the caret
  double _scrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _controller = _SqlController(text: widget.tab.sql);
    _controller.addListener(_onControllerChange);
    _bodyScroll = ScrollController()..addListener(_onScroll);
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

  void _onScroll() {
    final next = _bodyScroll.hasClients ? _bodyScroll.offset : 0.0;
    if ((next - _scrollOffset).abs() > 0.5) {
      setState(() => _scrollOffset = next);
    }
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
        context.read<AppState>().updateQuerySql(widget.tab, _controller.text);
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

  int get _lineCount => '\n'.allMatches(_controller.text).length + 1;

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
    widget.tab.view = QueryResultsView.results;
    final state = context.read<AppState>();
    final stmts = _statements.isNotEmpty
        ? _statements
        : parseSqlStatements(_controller.text);

    if (stmts.length <= 1) {
      await state.runQuery(widget.tab);
      return;
    }

    // The postgres extended query protocol doesn't allow multiple commands in
    // one prepared statement. Send each statement separately and surface the
    // last result; stop on the first failure so the user sees the error.
    for (final s in stmts) {
      await state.runQuery(widget.tab, sqlOverride: s.text);
      if (widget.tab.result?.isError ?? false) break;
    }
  }

  void _runStatement(SqlStatement stmt) {
    widget.tab.view = QueryResultsView.results;
    context.read<AppState>().runQuery(
          widget.tab,
          sqlOverride: stmt.text,
        );
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
  Widget _buildContent(AppState state, QueryTab tab) {
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
          foreignKeys: _resolveFks(state, tab.result!),
          onFollowForeignKey: (fk, value) =>
              state.followForeignKey(fk, value),
          findRowOwner: (col) => _findRowOwner(state, tab.result!, col),
          onFindRow: (table, col, value) =>
              state.findRowInTable(table, col, value),
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
    _bodyScroll.removeListener(_onScroll);
    _bodyScroll.dispose();
    widget.tab.removeListener(_onTabChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tab = widget.tab;

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
      child: _SqlCodeEditor(
        controller: _controller,
        focusNode: _focusNode,
        bodyScroll: _bodyScroll,
        scrollOffset: _scrollOffset,
        lineCount: _lineCount,
        statements: _statements,
        cursorStmt: _cursorStmt,
        onRunStatement: _runStatement,
      ),
    );

    return Column(
      children: [
        _Toolbar(
          tab: tab,
          onRunStatement:
              tab.running || _statements.isEmpty ? null : _runAtCursor,
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
              final available =
                  (constraints.maxHeight - dividerHeight - handleHeight)
                      .clamp(0.0, double.infinity);
              final fraction = state.preferences.queryResultsFraction;
              final resultsHeight = available * fraction;
              final editorHeight = available - resultsHeight;
              return Column(
                children: [
                  SizedBox(height: editorHeight, child: editor),
                  ResizeHandle(
                    axis: Axis.horizontal,
                    thickness: handleHeight,
                    onDrag: (dy) {
                      if (available <= 0) return;
                      state.preferences.setQueryResultsFraction(
                        fraction - dy / available,
                      );
                    },
                  ),
                  _ResultsDivider(tab: tab),
                  SizedBox(
                    height: resultsHeight,
                    child: Container(
                      color: AppColors.bg,
                      child: _buildContent(state, tab),
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
      cursor:
          enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onTap: onPressed,
      builder: (context, hovering) {
        final bg = !enabled
            ? AppColors.accent.withValues(alpha: 0.4)
            : (hovering ? AppColors.accentHover : AppColors.accent);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: 24,
          padding: const EdgeInsets.only(left: 9, right: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: Radii.brSm,
          ),
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
      cursor:
          enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
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
                : Colors.transparent,
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Container(
            constraints: BoxConstraints(
              minWidth: onAccent ? 13 : 16,
              minHeight: onAccent ? 13 : 16,
            ),
            padding: EdgeInsets.symmetric(horizontal: onAccent ? 3 : 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: onAccent
                  ? Colors.white.withValues(alpha: 0.18)
                  : AppColors.surface2,
              borderRadius: BorderRadius.circular(onAccent ? 3 : 4),
              border: onAccent
                  ? null
                  : Border.all(color: AppColors.border),
            ),
            child: Text(
              parts[i],
              style: AppTheme.mono(
                size: onAccent ? 9.5 : 10,
                color: onAccent ? Colors.white : AppColors.textSecondary,
                weight: FontWeight.w500,
              ),
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
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          _RdTab(
            label: 'Results',
            active: tab.view == QueryResultsView.results,
            onTap: () => tab.view = QueryResultsView.results,
          ),
          const SizedBox(width: 12),
          _RdTab(
            label: 'Plan',
            active: tab.view == QueryResultsView.plan,
            onTap: () => tab.view = QueryResultsView.plan,
          ),
          const SizedBox(width: 12),
          _RdTab(
            label: 'Messages',
            active: tab.view == QueryResultsView.messages,
            onTap: () => tab.view = QueryResultsView.messages,
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
                      color: active
                          ? AppColors.accent
                          : AppColors.textMuted,
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
              child: Container(
                height: 1,
                color: AppColors.accent,
              ),
            ),
        ],
      ),
    );
  }
}

/// Highlighted text editor — Flutter `TextField` with a controller that
/// returns a pgsql-highlighted `TextSpan` tree, plus a hand-built gutter
/// (line numbers + ▶ run icons) on the left.
///
/// We dropped `flutter_code_editor` because its gutter wraps content in
/// hidden `Padding` + `Table` layout whose digit positions don't share
/// metrics with the body `TextField`, so line numbers always drifted off
/// the source baseline.  Owning the editor end-to-end means a digit at
/// line `i`, the ▶ icon at line `i`, and the source character at line
/// `i` all derive their Y from the same `_lineTop(i, scroll)` and the
/// same body font metrics — alignment is guaranteed by construction.
class _SqlCodeEditor extends StatelessWidget {
  const _SqlCodeEditor({
    required this.controller,
    required this.focusNode,
    required this.bodyScroll,
    required this.scrollOffset,
    required this.lineCount,
    required this.statements,
    required this.cursorStmt,
    required this.onRunStatement,
  });

  final _SqlController controller;
  final FocusNode focusNode;
  final ScrollController bodyScroll;
  final double scrollOffset;
  final int lineCount;
  final List<SqlStatement> statements;
  final int? cursorStmt;
  final void Function(SqlStatement) onRunStatement;

  @override
  Widget build(BuildContext context) {
    final bodyStyle = GoogleFonts.jetBrainsMono(
      fontSize: _editorFontSize,
      height: _editorLineHeight,
      color: AppColors.textPrimary,
    );

    final activeStmt = cursorStmt != null && cursorStmt! >= 1 &&
            cursorStmt! <= statements.length
        ? statements[cursorStmt! - 1]
        : null;

    return ClipRect(
      child: Stack(
        children: [
          // Soft accent gradient on the lines of the active statement —
          // the design's `.editor .code .line.active` rule, painted as one
          // Positioned overlay across the statement's line range.
          if (activeStmt != null)
            Positioned(
              left: _gutterWidth,
              top: _lineTop(activeStmt.startLine, scrollOffset),
              right: 0,
              height: _editorLineBox *
                  ('\n'.allMatches(activeStmt.text).length + 1),
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        AppColors.accent.withValues(alpha: 0.06),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.8],
                    ),
                  ),
                ),
              ),
            ),
          // Body: gutter background + TextField with syntax highlighting.
          // `decoration: null` skips the InputDecorator entirely so the
          // EditableText underneath renders at the exact Y we wrap it at
          // — no hidden contentPadding, no baseline alignment, no
          // unaccounted offset between body and gutter overlay.
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: _gutterWidth,
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  border: Border(
                    right: BorderSide(color: AppColors.hairline, width: 1),
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  color: AppColors.bg,
                  padding: const EdgeInsets.symmetric(
                    horizontal: _editorBodyLeftPad,
                    vertical: _editorTopPad,
                  ),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    scrollController: bodyScroll,
                    maxLines: null,
                    minLines: null,
                    expands: true,
                    cursorColor: AppColors.accent,
                    style: bodyStyle,
                    decoration: null,
                  ),
                ),
              ),
            ],
          ),
          // Line-number digits — one Positioned per line, scroll-synced.
          for (var i = 0; i < lineCount; i++)
            _GutterLineNumber(
              line: i + 1,
              top: _lineTop(i, scrollOffset),
            ),
          // ▶ run icons — one per parsed statement.
          for (final stmt in statements)
            _RunStmtIcon(
              stmt: stmt,
              top: _lineTop(stmt.startLine, scrollOffset),
              onTap: () => onRunStatement(stmt),
            ),
        ],
      ),
    );
  }
}

/// `TextEditingController` that returns a pgsql-highlighted `TextSpan`
/// tree from the `highlight` package. Same grammar + theme map the
/// schema viewer uses, so SQL anywhere in the app reads the same way.
class _SqlController extends TextEditingController {
  _SqlController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    if (text.isEmpty) return TextSpan(text: '', style: base);
    final parsed = highlight.parse(text, language: 'pgsql');
    return TextSpan(
      style: base,
      children: highlightNodesToSpans(parsed.nodes, base, apertureCodeStyles),
    );
  }
}

/// Builds a column-name → FK lookup for a raw query result. Prefers the
/// source-relation OID exposed by the wire protocol so the FK action targets
/// the *actual* table the column came from; falls back to the catalog-wide
/// aggregation when the column is an expression (no source relation).
Map<String, DbForeignKey> _resolveFks(AppState state, QueryResult result) {
  final schemas = result.columnSchemas;
  if (schemas == null) return state.aggregatedForeignKeys;
  final out = <String, DbForeignKey>{};
  for (final schema in schemas) {
    final precise = state.findForeignKey(schema.tableOid, schema.name);
    if (precise != null) {
      out[schema.name] = precise;
    } else if (!schema.hasSourceRelation) {
      final guess = state.aggregatedForeignKeys[schema.name];
      if (guess != null) out[schema.name] = guess;
    }
  }
  return out;
}

/// Returns the relation whose PK is [columnName], preferring the source
/// relation OID from the wire protocol when present. Falls back to the
/// ambiguity-safe catalog lookup otherwise.
DbTable? _findRowOwner(AppState state, QueryResult result, String columnName) {
  final schemas = result.columnSchemas;
  if (schemas == null) return state.findPrimaryKeyOwner(columnName);
  for (final schema in schemas) {
    if (schema.name != columnName) continue;
    return state.findPrimaryKeyOwnerByOid(schema.tableOid, columnName);
  }
  return state.findPrimaryKeyOwner(columnName);
}

class _RunStmtIcon extends StatelessWidget {
  const _RunStmtIcon({
    required this.stmt,
    required this.top,
    required this.onTap,
  });

  final SqlStatement stmt;
  final double top;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _runIconLeft,
      top: top,
      width: _runIconColumnWidth,
      height: _editorLineBox,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Tooltip(
            message: 'Run statement (⌘⇧↵)',
            waitDuration: const Duration(milliseconds: 400),
            // Render the icon as a WidgetSpan inside a Text.rich that
            // uses the body's text style.  PlaceholderAlignment.middle
            // anchors the icon to the same alphabetic middle the source
            // characters sit at, so ▶ lines up with the digit and the
            // SELECT keyword on the same row.
            child: Text.rich(
              TextSpan(
                style: GoogleFonts.jetBrainsMono(
                  fontSize: _editorFontSize,
                  height: _editorLineHeight,
                ),
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 14,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GutterLineNumber extends StatelessWidget {
  const _GutterLineNumber({required this.line, required this.top});

  final int line;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: top,
      width: _gutterWidth - _runIconColumnWidth - _gutterRightPad,
      height: _editorLineBox,
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Text(
          '$line',
          textAlign: TextAlign.right,
          style: GoogleFonts.jetBrainsMono(
            fontSize: _editorFontSize,
            height: _editorLineHeight,
            color: AppColors.text4,
          ),
        ),
      ),
    );
  }
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
    final state = context.watch<AppState>();
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
            PbStat(
              head: '${result.elapsed.inMilliseconds}',
              tail: 'ms',
            ),
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
            PbStat(
              head: 'refreshed ',
              mid: formatPagebarClock(refreshedAt),
            ),
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
                    color: result.isError
                        ? AppColors.error
                        : AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  result.isError ? 'error' : 'success',
                  style: AppTheme.mono(
                    size: 10.5,
                    color: result.isError
                        ? AppColors.error
                        : AppColors.success,
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
            onManualRefresh: () =>
                state.runQuery(tab, sqlOverride: lastRunSql),
            onSetInterval: (d) => state.setQueryAutoRefresh(tab, d),
          ),
        ],
      ),
    );
  }
}


