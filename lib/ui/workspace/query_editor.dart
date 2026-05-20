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
import '../export/export_dialog.dart';
import '../widgets/common.dart';
import 'results_grid.dart';

/// Syntax-highlighted SQL editor over the result grid.
///
/// - Autosaves the text to the active connection's SavedQuery list (400ms
///   debounce) so queries survive restarts.
/// - Parses statements as you type; the gutter shows a ▶ icon next to each
///   statement's first line, click to run just that block.
/// - ⌘↵ runs everything; ⌘⇧↵ runs the statement under the cursor.
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
    _recomputeStatements();
    _recomputeCursorStmt();
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

  void _openExport() {
    final result = widget.tab.result;
    if (result == null) return;
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    showExportDialog(
      context,
      target: ExportTarget(
        suggestedFilename: 'query_$timestamp.csv',
        currentResult: result,
      ),
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _controller.removeListener(_onControllerChange);
    _controller.dispose();
    _bodyScroll.removeListener(_onScroll);
    _bodyScroll.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tab = widget.tab;

    return Column(
      children: [
        _Toolbar(
          tab: tab,
          statementCount: _statements.length,
          cursorStmt: _cursorStmt,
          onRun: tab.running ? null : _runAll,
          onExport: tab.result == null ? null : _openExport,
        ),
        Expanded(
          flex: 2,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                  _runAll,
              const SingleActivator(
                LogicalKeyboardKey.enter,
                meta: true,
                shift: true,
              ): _runAtCursor,
            },
            child: _SqlCodeEditor(
              controller: _controller,
              focusNode: _focusNode,
              bodyScroll: _bodyScroll,
              scrollOffset: _scrollOffset,
              lineCount: _lineCount,
              statements: _statements,
              onRunStatement: _runStatement,
            ),
          ),
        ),
        const Divider(height: 1, color: AppColors.borderStrong),
        Expanded(
          flex: 3,
          child: Container(
            color: AppColors.bg,
            child: tab.result == null
                ? const EmptyState(
                    icon: Icons.terminal,
                    title: 'Run a query',
                    message:
                        'Write SQL above and press ⌘↵ (or click ▶ in the gutter for a single statement).',
                  )
                : ResultsGrid(
                    result: tab.result!,
                    widths: tab.columnWidths,
                    foreignKeys: _resolveFks(state, tab.result!),
                    onFollowForeignKey: (fk, value) =>
                        state.followForeignKey(fk, value),
                    findRowOwner: (col) =>
                        _findRowOwner(state, tab.result!, col),
                    onFindRow: (table, col, value) =>
                        state.findRowInTable(table, col, value),
                  ),
          ),
        ),
        _StatusFooter(tab: tab, connected: state.activeConnection != null),
      ],
    );
  }
}

/// Query editor toolbar — synth-panel layout with hairline rails grouping
/// the run action, the multi-statement status readout, and the export action.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.tab,
    required this.statementCount,
    required this.cursorStmt,
    required this.onRun,
    required this.onExport,
  });

  final QueryTab tab;
  final int statementCount;
  final int? cursorStmt;
  final VoidCallback? onRun;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final multi = statementCount > 1;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: Insets.md),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // ── primary run ──
          AppButton(
            label: tab.running ? 'Running…' : 'Run',
            icon: Icons.play_arrow,
            primary: true,
            onPressed: onRun,
          ),
          const SizedBox(width: 7),
          const KbdChip('⌘↵'),
          // ── statement readout (only when multi-statement) ──
          // No standalone "At cursor" button — the gutter ▶ icons + ⌘⇧↵
          // shortcut cover that path.
          if (multi) ...[
            const Rail(),
            _StatementStatus(
              count: statementCount,
              cursorStmt: cursorStmt,
            ),
            const SizedBox(width: 8),
            const KbdChip('⌘⇧↵'),
          ],
          const Spacer(),
          if (tab.running)
            const _RunningIndicator()
          else if (tab.result != null)
            _LastStatus(tab: tab),
          const Rail(),
          IconAction(
            icon: Icons.ios_share,
            tooltip: 'Export…',
            onPressed: onExport,
          ),
        ],
      ),
    );
  }
}

/// Compact readout: `3 statements · on #2` — number bolded, rest muted.
class _StatementStatus extends StatelessWidget {
  const _StatementStatus({required this.count, required this.cursorStmt});
  final int count;
  final int? cursorStmt;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: AppTheme.mono(size: 10.5, color: AppColors.textMuted),
        children: [
          TextSpan(
            text: '$count',
            style: AppTheme.mono(
              size: 10.5,
              color: AppColors.textSecondary,
              weight: FontWeight.w600,
            ),
          ),
          const TextSpan(text: ' statements'),
          if (cursorStmt != null) ...[
            const TextSpan(text: '  ·  on '),
            TextSpan(
              text: '#$cursorStmt',
              style: AppTheme.mono(
                size: 10.5,
                color: AppColors.accent,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RunningIndicator extends StatelessWidget {
  const _RunningIndicator();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.6,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'running',
          style: AppTheme.mono(size: 10.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

/// Tiny end-of-toolbar status — rows / ms — when a result is loaded but no
/// run is in progress. Mirrors the bottom status bar in a glanceable form.
class _LastStatus extends StatelessWidget {
  const _LastStatus({required this.tab});
  final QueryTab tab;

  @override
  Widget build(BuildContext context) {
    final r = tab.result!;
    final isError = r.isError;
    final color = isError ? AppColors.error : AppColors.success;
    final summary = isError
        ? 'error'
        : r.hasColumns
            ? '${r.rows.length} rows'
            : '${r.affectedRows ?? 0} rows affected';

    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          summary,
          style: AppTheme.mono(size: 10.5, color: AppColors.textMuted),
        ),
        const SizedBox(width: 8),
        Text(
          '${r.elapsed.inMilliseconds}ms',
          style: AppTheme.mono(size: 10.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _StatusFooter extends StatelessWidget {
  const _StatusFooter({required this.tab, required this.connected});

  final QueryTab tab;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final result = tab.result;
    String message;
    Color color;
    if (!connected) {
      message = 'Not connected';
      color = AppColors.textMuted;
    } else if (result == null) {
      message = 'Ready';
      color = AppColors.textMuted;
    } else if (result.isError) {
      message = 'Error';
      color = AppColors.error;
    } else if (result.hasColumns) {
      message = '${result.rows.length} rows';
      color = AppColors.success;
    } else {
      message = '${result.affectedRows ?? 0} rows affected';
      color = AppColors.success;
    }

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: Insets.md),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            message,
            style: AppTheme.mono(size: 11, color: AppColors.textSecondary),
          ),
          const Spacer(),
          if (result != null)
            Text(
              '${result.elapsed.inMilliseconds} ms',
              style: AppTheme.mono(size: 11, color: AppColors.textMuted),
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
    required this.onRunStatement,
  });

  final _SqlController controller;
  final FocusNode focusNode;
  final ScrollController bodyScroll;
  final double scrollOffset;
  final int lineCount;
  final List<SqlStatement> statements;
  final void Function(SqlStatement) onRunStatement;

  @override
  Widget build(BuildContext context) {
    final bodyStyle = GoogleFonts.jetBrainsMono(
      fontSize: _editorFontSize,
      height: _editorLineHeight,
      color: AppColors.textPrimary,
    );

    return ClipRect(
      child: Stack(
        children: [
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
                color: AppColors.surface,
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
                children: const [
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
            color: AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}
