import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:highlight/languages/pgsql.dart';
import 'package:provider/provider.dart';

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

class _QueryEditorState extends State<QueryEditor> {
  late final CodeController _controller;
  String _lastDictKey = '';
  Timer? _saveTimer;
  List<SqlStatement> _statements = const [];
  Set<int> _runnableLines = const {};
  int? _cursorStmt; // 1-based statement index containing the caret

  @override
  void initState() {
    super.initState();
    _controller = CodeController(text: widget.tab.sql, language: pgsql);
    _controller.addListener(_onControllerChange);
    _recomputeStatements();
    _recomputeCursorStmt();
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
    _runnableLines = {for (final s in _statements) s.startLine + 1};
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

  void _refreshAutocomplete(AppState state) {
    final words = <String>{};
    for (final schema in state.schemas) {
      words.add(schema.name);
      for (final table in schema.tables) {
        words.add(table.name);
      }
    }
    words.addAll(state.loadedColumnNames);
    final key = '${words.length}:${words.join("|").hashCode}';
    if (key == _lastDictKey) return;
    _lastDictKey = key;
    _controller.autocompleter.setCustomWords(words.toList());
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
    super.dispose();
  }

  /// Custom gutter line builder — line number first, then a play icon
  /// (WidgetSpan) on each runnable line. Click runs just that statement.
  TextSpan _gutterLine(int line, TextStyle? style) {
    if (!_runnableLines.contains(line)) {
      return TextSpan(text: '$line', style: style);
    }
    final stmt = _statements.firstWhere((s) => s.startLine + 1 == line);
    return TextSpan(
      children: [
        TextSpan(text: '$line', style: style),
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _runStatement(stmt),
              child: const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 13,
                  color: AppColors.success,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _refreshAutocomplete(state);
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
            child: Container(
              color: AppColors.bg,
              child: CodeTheme(
                data: CodeThemeData(styles: apertureCodeStyles),
                child: CodeField(
                  controller: _controller,
                  expands: true,
                  wrap: false,
                  background: AppColors.bg,
                  cursorColor: AppColors.accent,
                  lineNumberBuilder: _gutterLine,
                  textStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    height: 1.45,
                    color: AppColors.textPrimary,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: Insets.md,
                    vertical: Insets.sm,
                  ),
                  gutterStyle: GutterStyle(
                    width: 60,
                    margin: 8,
                    background: AppColors.surface,
                    textStyle: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ),
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
                    foreignKeys: state.aggregatedForeignKeys,
                    onFollowForeignKey: (fk, value) =>
                        state.followForeignKey(fk, value),
                    findRowOwner: (col) =>
                        state.findPrimaryKeyOwner(col),
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
