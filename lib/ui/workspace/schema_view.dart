import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../../theme/code_theme.dart';
import '../widgets/common.dart';

/// Renders a [SchemaTab] in the design's "article" style: centered title,
/// muted relation subtitle, eyebrow section heading, and a surface DDL block
/// with selectable, syntax-highlighted source.
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
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.data_object, size: 13, color: AppColors.accent),
          const SizedBox(width: 7),
          RichText(
            text: TextSpan(
              style: AppTheme.mono(size: 11.5, weight: FontWeight.w600),
              children: [
                TextSpan(
                  text: '${tab.table.schema}.',
                  style: AppTheme.mono(
                    size: 11.5,
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
      return Center(
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
      return const EmptyState(icon: Icons.code, title: 'No DDL');
    }

    final base = AppTheme.mono(
      size: 12,
      color: AppColors.textPrimary,
    ).copyWith(height: 1.65);
    final raw = tab.ddl!;
    final ddl = raw.endsWith('\n') ? raw.substring(0, raw.length - 1) : raw;
    final parsed = highlight.parse(ddl, language: 'pgsql');

    return Container(
      color: AppColors.bg,
      child: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(40, 28, 40, 60),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tab.table.name,
                    style: AppTheme.mono(
                      size: 18,
                      color: AppColors.textPrimary,
                      weight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${tab.table.schema} · ${tab.table.isView ? 'view' : 'table'}',
                    style: AppTheme.mono(
                      size: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _SectionTitle(label: 'DDL'),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: Radii.brSm,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
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
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: AppTheme.mono(
            size: 10.5,
            color: AppColors.textMuted,
            weight: FontWeight.w600,
          ).copyWith(letterSpacing: 0.08 * 10.5),
        ),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: AppColors.hairline)),
      ],
    );
  }
}
