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

  @override
  void initState() {
    super.initState();
    _controller = CodeController(text: widget.tab.sql, language: pgsql);
    _controller.addListener(_onTextChanged);
    _recomputeStatements();
  }

  void _onTextChanged() {
    final text = _controller.text;
    if (widget.tab.sql == text) return;
    widget.tab.sql = text;
    _recomputeStatements();
    setState(() {});

    // Debounced autosave into the active connection's SavedQuery list.
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      context.read<AppState>().updateQuerySql(widget.tab, _controller.text);
    });
  }

  void _recomputeStatements() {
    _statements = parseSqlStatements(_controller.text);
    _runnableLines = {for (final s in _statements) s.startLine + 1};
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

  void _runAll() {
    widget.tab.sql = _controller.text;
    context.read<AppState>().runQuery(widget.tab);
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
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  /// Custom gutter line builder — injects a play icon (WidgetSpan) on each
  /// runnable line so the user can fire a single statement with one click.
  TextSpan _gutterLine(int line, TextStyle? style) {
    if (!_runnableLines.contains(line)) {
      return TextSpan(text: '$line', style: style);
    }
    final stmt = _statements.firstWhere((s) => s.startLine + 1 == line);
    return TextSpan(
      children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _runStatement(stmt),
              child: const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 12,
                  color: AppColors.success,
                ),
              ),
            ),
          ),
        ),
        TextSpan(text: '$line', style: style),
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
          onRun: tab.running ? null : _runAll,
          onRunAtCursor: tab.running || _statements.isEmpty ? null : _runAtCursor,
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
                  ),
          ),
        ),
        _StatusFooter(tab: tab, connected: state.activeConnection != null),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.tab,
    required this.statementCount,
    required this.onRun,
    required this.onRunAtCursor,
    required this.onExport,
  });

  final QueryTab tab;
  final int statementCount;
  final VoidCallback? onRun;
  final VoidCallback? onRunAtCursor;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: Insets.md),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          AppButton(
            label: tab.running ? 'Running…' : 'Run all',
            icon: Icons.play_arrow,
            primary: true,
            onPressed: onRun,
          ),
          const SizedBox(width: Insets.sm),
          Text(
            '⌘↵',
            style: AppTheme.mono(size: 11, color: AppColors.textMuted),
          ),
          if (statementCount > 1) ...[
            const SizedBox(width: Insets.md),
            AppButton(
              label: 'Run at cursor',
              icon: Icons.adjust,
              onPressed: onRunAtCursor,
            ),
            const SizedBox(width: Insets.sm),
            Text(
              '⌘⇧↵',
              style: AppTheme.mono(size: 11, color: AppColors.textMuted),
            ),
            const SizedBox(width: Insets.md),
            _StatementCountBadge(count: statementCount),
          ],
          const Spacer(),
          if (tab.running) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: Insets.sm),
          ],
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

class _StatementCountBadge extends StatelessWidget {
  const _StatementCountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: Radii.brSm,
      ),
      child: Text(
        '$count stmts',
        style: AppTheme.mono(
          size: 10,
          color: AppColors.accent,
          weight: FontWeight.w600,
        ),
      ),
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
