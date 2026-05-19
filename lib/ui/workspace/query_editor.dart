import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:highlight/languages/pgsql.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'results_grid.dart';

/// Syntax-highlighted SQL editor over a paginated result grid. Autocomplete
/// is fed from the active connection's schema and any columns we've loaded.
class QueryEditor extends StatefulWidget {
  const QueryEditor({super.key, required this.tab});

  final QueryTab tab;

  @override
  State<QueryEditor> createState() => _QueryEditorState();
}

class _QueryEditorState extends State<QueryEditor> {
  late final CodeController _controller;
  String _lastDictKey = '';

  @override
  void initState() {
    super.initState();
    _controller = CodeController(
      text: widget.tab.sql,
      language: pgsql,
    );
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    widget.tab.sql = _controller.text;
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

  void _run() {
    widget.tab.sql = _controller.text;
    context.read<AppState>().runQuery(widget.tab);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _refreshAutocomplete(state);
    final tab = widget.tab;

    return Column(
      children: [
        _Toolbar(tab: tab, onRun: tab.running ? null : _run),
        Expanded(
          flex: 2,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                  _run,
            },
            child: Container(
              color: AppColors.bg,
              child: CodeTheme(
                data: _codeTheme,
                child: CodeField(
                  controller: _controller,
                  expands: true,
                  wrap: false,
                  background: AppColors.bg,
                  cursorColor: AppColors.accent,
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
                    width: 44,
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
                    message: 'Write SQL above and press ⌘↵ to execute.',
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

  static final CodeThemeData _codeTheme = CodeThemeData(styles: {
    'root': const TextStyle(color: AppColors.textPrimary),
    'keyword': const TextStyle(
      color: AppColors.sqlKeyword,
      fontWeight: FontWeight.w500,
    ),
    'built_in': const TextStyle(color: AppColors.sqlFunction),
    'type': const TextStyle(color: AppColors.sqlKeyword),
    'literal': const TextStyle(color: AppColors.sqlNumber),
    'number': const TextStyle(color: AppColors.sqlNumber),
    'string': const TextStyle(color: AppColors.sqlString),
    'symbol': const TextStyle(color: AppColors.sqlString),
    'comment': const TextStyle(
      color: AppColors.sqlComment,
      fontStyle: FontStyle.italic,
    ),
    'meta': const TextStyle(color: AppColors.sqlComment),
    'operator': const TextStyle(color: AppColors.textSecondary),
    'punctuation': const TextStyle(color: AppColors.textSecondary),
  });
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.tab, required this.onRun});

  final QueryTab tab;
  final VoidCallback? onRun;

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
            label: tab.running ? 'Running…' : 'Run',
            icon: Icons.play_arrow,
            primary: true,
            onPressed: onRun,
          ),
          const SizedBox(width: Insets.sm),
          Text(
            '⌘↵',
            style: AppTheme.mono(size: 11, color: AppColors.textMuted),
          ),
          const Spacer(),
          if (tab.running)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            ),
        ],
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
