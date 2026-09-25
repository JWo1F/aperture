import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:highlight/highlight.dart' show highlight;

import '../../models/db_object.dart';
import '../../models/schema_object.dart';
import '../../state/app_globals.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../../theme/code_theme.dart';
import '../../theme/hugeicons.dart';
import '../widgets/common.dart';
import '../widgets/segmented_choice.dart';
import '../widgets/table_glyph.dart';
import 'object_view/article.dart';
import 'object_view/info_body.dart';

/// The object tab: a toolbar naming the object, and either its info page
/// (relations only) or its highlighted `CREATE` statement.
class SchemaView extends StatelessWidget {
  const SchemaView({super.key, required this.tab});

  final SchemaTab tab;

  @override
  Widget build(BuildContext context) {
    final table = tab.table;
    return Column(
      children: [
        _Toolbar(tab: tab),
        Expanded(
          child: tab.view == ObjectView.info && table != null
              ? InfoBody(table: table)
              : _DdlBody(tab: tab),
        ),
      ],
    );
  }
}

Widget _objectIcon(SchemaObject object, Color color, double size) =>
    switch (object) {
      RelationObject() => TableGlyph(size: size, color: color),
      RoutineObject(routine: final r) => Icon(
        r.kind == DbRoutineKind.procedure ? Hgi.playSquare : Hgi.functionSquare,
        size: size,
        color: color,
      ),
      SequenceObject() => Icon(Hgi.sortingOne9, size: size, color: color),
      EnumObject() => Icon(Hgi.listView, size: size, color: color),
      DomainObject() => Icon(Hgi.shapes, size: size, color: color),
    };

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.tab});

  final SchemaTab tab;

  void _copy() {
    final ddl = tab.ddl;
    if (ddl == null) return;
    Clipboard.setData(ClipboardData(text: ddl));
    appState.toasts.success('Copied DDL to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    final object = tab.object;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _objectIcon(object, AppColors.accent, 13),
          const SizedBox(width: 8),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${object.schema}.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  TextSpan(text: object.name),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.mono(size: 11.5, weight: FontWeight.w600),
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
              object.kindLabel,
              style: AppTheme.mono(
                size: 10,
                color: AppColors.accent,
                weight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          if (tab.hasInfo) ...[
            SegmentedChoice<ObjectView>(
              value: tab.view,
              onChanged: tab.setView,
              options: const [
                (ObjectView.info, 'Info'),
                (ObjectView.ddl, 'DDL'),
              ],
            ),
            const SizedBox(width: 6),
          ],
          IconAction(
            icon: Hgi.refresh,
            tooltip: 'Reload DDL',
            onPressed: tab.loading
                ? null
                : () => appState.tabsController.reloadObjectDdl(tab),
            busy: tab.loading,
          ),
          IconAction(
            icon: Hgi.copy01,
            tooltip: 'Copy DDL',
            onPressed: tab.ddl == null ? null : _copy,
          ),
        ],
      ),
    );
  }
}

class _DdlBody extends StatelessWidget {
  const _DdlBody({required this.tab});

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
        icon: Hgi.alertCircle,
        title: 'Could not load the DDL',
        message: tab.error,
      );
    }
    if (tab.ddl == null) {
      return const EmptyState(icon: Hgi.sourceCode, title: 'No DDL');
    }

    final base = AppTheme.mono(
      size: 12,
      color: AppColors.textPrimary,
    ).copyWith(height: 1.65);
    final raw = tab.ddl!;
    final ddl = raw.endsWith('\n') ? raw.substring(0, raw.length - 1) : raw;
    final parsed = highlight.parse(ddl, language: 'pgsql');
    final object = tab.object;

    return Article(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              object.name,
              style: AppTheme.mono(
                size: 18,
                color: AppColors.textPrimary,
                weight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${object.schema} · ${object.kindLabel}',
              style: AppTheme.mono(size: 11.5, color: AppColors.textMuted),
            ),
          ],
        ),
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
    );
  }
}
