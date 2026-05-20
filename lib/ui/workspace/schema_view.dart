import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../../theme/code_theme.dart';
import '../widgets/common.dart';

/// Renders a [SchemaTab] — the reconstructed CREATE TABLE DDL with indexes
/// and constraints. Uses `highlight`'s pgsql grammar through
/// [highlightNodesToSpans] so the text stays inside a [SelectableText.rich],
/// keeping the whole DDL selectable / copyable.
class SchemaView extends StatelessWidget {
  const SchemaView({super.key, required this.tab});

  final SchemaTab tab;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Column(
      children: [
        _Toolbar(tab: tab, state: state),
        Expanded(child: _Body(tab: tab)),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.tab, required this.state});
  final SchemaTab tab;
  final AppState state;

  void _copy(BuildContext context) {
    final ddl = tab.ddl;
    if (ddl == null) return;
    Clipboard.setData(ClipboardData(text: ddl));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        backgroundColor: AppColors.surfaceAlt,
        content: Text(
          'Copied DDL',
          style: AppTheme.mono(size: 11.5, color: AppColors.textPrimary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: Insets.md),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.data_object,
            size: 14,
            color: AppColors.accent,
          ),
          const SizedBox(width: 7),
          RichText(
            text: TextSpan(
              style: AppTheme.mono(size: 12, weight: FontWeight.w600),
              children: [
                TextSpan(
                  text: '${tab.table.schema}.',
                  style: AppTheme.mono(
                    size: 12,
                    color: AppColors.textMuted,
                    weight: FontWeight.w400,
                  ),
                ),
                TextSpan(text: tab.table.name),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: Radii.brSm,
            ),
            child: Text(
              'schema',
              style: AppTheme.mono(
                size: 10,
                color: AppColors.accent,
                weight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          IconAction(
            icon: Icons.refresh,
            tooltip: 'Reload',
            onPressed: tab.loading ? null : () => state.reloadSchema(tab),
            busy: tab.loading,
          ),
          IconAction(
            icon: Icons.copy,
            tooltip: 'Copy DDL',
            onPressed: tab.ddl == null ? null : () => _copy(context),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.tab});
  final SchemaTab tab;

  @override
  Widget build(BuildContext context) {
    if (tab.loading && tab.ddl == null) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.accent,
          ),
        ),
      );
    }
    if (tab.error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Could not load schema',
        message: tab.error,
      );
    }
    if (tab.ddl == null) {
      return const EmptyState(
        icon: Icons.code,
        title: 'No DDL',
      );
    }

    final base = AppTheme.mono(size: 12, color: AppColors.textPrimary);
    // Trim trailing newline so line numbers match the rendered lines exactly.
    final raw = tab.ddl!;
    final ddl = raw.endsWith('\n')
        ? raw.substring(0, raw.length - 1)
        : raw;
    final lineCount = '\n'.allMatches(ddl).length + 1;
    final parsed = highlight.parse(ddl, language: 'pgsql');

    return Container(
      color: AppColors.bg,
      child: SingleChildScrollView(
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LineNumbers(count: lineCount, baseStyle: base),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(
                    14,
                    Insets.md,
                    Insets.md,
                    Insets.md,
                  ),
                  child: SelectableText.rich(
                    TextSpan(
                      children: highlightNodesToSpans(
                        parsed.nodes,
                        base,
                        apertureCodeStyles,
                      ),
                    ),
                    style: base,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineNumbers extends StatelessWidget {
  const _LineNumbers({required this.count, required this.baseStyle});
  final int count;

  /// Body text style. Line numbers inherit its size + height so each row
  /// aligns exactly with its source line — different sizes drift over many
  /// lines and make numbers look one short at the bottom.
  final TextStyle baseStyle;

  @override
  Widget build(BuildContext context) {
    final style = baseStyle.copyWith(color: AppColors.textMuted);
    return SelectionContainer.disabled(
      child: Container(
        color: AppColors.surface,
        padding: const EdgeInsets.fromLTRB(10, Insets.md, 10, Insets.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 1; i <= count; i++) Text('$i', style: style),
          ],
        ),
      ),
    );
  }
}
