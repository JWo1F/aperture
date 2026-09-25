import 'package:flutter/material.dart';

import '../../../models/count_format.dart';
import '../../../models/db_catalog.dart';
import '../../../models/db_object.dart';
import '../../../models/schema_object.dart';
import '../../../state/app_globals.dart';
import '../../../state/workspace_tab.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import '../../widgets/common.dart';
import '../../widgets/table_glyph.dart';
import 'article.dart';
import 'plain_language.dart';

/// A relation described for someone who doesn't read DDL: what each column
/// holds, how the table connects to others, and what is fast to look up.
class InfoBody extends StatelessWidget {
  const InfoBody({super.key, required this.table});

  final DbTable table;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState.catalog,
      builder: (context, _) {
        final catalog = appState.catalog.catalog;
        return Article(
          children: [
            _Heading(table: table),
            if (!catalog.hasPhase(CatalogPhase.columns))
              const ArticleNote(text: 'Loading details…')
            else
              ..._sections(catalog),
          ],
        );
      },
    );
  }

  List<Widget> _sections(DatabaseCatalog catalog) {
    final columns = catalog.columnsFor(table);
    final keys = catalog.keysFor(table);
    final outgoing = catalog.foreignKeysFor(table);
    final incoming = [
      for (final e in catalog.foreignKeysByOid.entries)
        for (final fk in e.value)
          if (fk.refTableOid == table.oid && catalog.relation(e.key) != null)
            (source: catalog.relation(e.key)!, fk: fk),
    ];
    final indexes = catalog.indexesFor(table);
    final uniqueColumns = {
      for (final k in keys)
        if (!k.isPrimary && k.columns.length == 1) k.columns.single,
      for (final i in indexes)
        if (i.unique && i.columns.length == 1) i.columns.single,
    };
    final links = {
      for (final fk in outgoing)
        if (fk.isSingleColumn) fk.localColumn: fk,
    };

    return [
      ArticleSection(
        title: 'Columns',
        count: columns.length,
        children: [
          if (columns.isEmpty)
            const ArticleNote(text: 'No columns.')
          else
            for (final c in columns)
              _ColumnRow(
                column: c,
                plain: plainType(
                  c.dataType,
                  enums: catalog.enums,
                  domains: catalog.domains,
                ),
                unique: uniqueColumns.contains(c.name),
                link: links[c.name],
              ),
        ],
      ),
      if (!table.isView)
        ArticleSection(
          title: 'Relationships',
          count: outgoing.length + incoming.length,
          children: [
            if (outgoing.isEmpty && incoming.isEmpty)
              const ArticleNote(text: 'Not linked to other tables.'),
            for (final fk in outgoing)
              _RelationRow(
                icon: Hgi.arrowRight02,
                sentence:
                    'Each row points to a row in ${plainName(fk.refTable)}',
                via: plainColumns(fk.localColumns),
                target: catalog.relation(fk.refTableOid),
              ),
            for (final (:source, :fk) in incoming)
              _RelationRow(
                icon: Hgi.arrowLeft02,
                sentence:
                    'Rows in ${plainName(source.name)} point to this '
                    '${table.kindLabelForProse}',
                via: plainColumns(fk.localColumns),
                target: source,
              ),
          ],
        ),
      if (indexes.isNotEmpty)
        ArticleSection(
          title: 'Speed-ups',
          count: indexes.length,
          children: [
            for (final i in indexes)
              _PlainRow(icon: Hgi.flash, text: plainIndex(i), detail: i.name),
          ],
        ),
    ];
  }
}

extension on DbTable {
  String get kindLabelForProse => RelationObject(this).kindLabel;
}

class _Heading extends StatelessWidget {
  const _Heading({required this.table});

  final DbTable table;

  @override
  Widget build(BuildContext context) {
    final kind = RelationObject(table).kindLabel;
    final facts = [
      '${kind[0].toUpperCase()}${kind.substring(1)} in ${table.schema}',
      if (table.rowEstimate != null)
        '≈${compactCount(table.rowEstimate!)} rows',
      if (table.sizeBytes != null) compactBytes(table.sizeBytes!),
    ];
    final explanation = switch (table.kind) {
      DbRelationKind.view =>
        'A saved query that reads from other tables. It stores no data of '
            'its own — every read runs the query again.',
      DbRelationKind.materializedView =>
        "A saved query whose result is stored like a table. It shows the "
            'data as of its last refresh, not live.',
      DbRelationKind.table when table.partitioned =>
        'A table split into partitions by a key. Rows live in the '
            'partitions; this table reads them all as one.',
      DbRelationKind.table => null,
    };
    final comment = table.comment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TableGlyph(size: 18, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: SelectableText(
                table.name,
                style: AppTheme.mono(
                  size: 20,
                  weight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            AppButton(
              label: 'Open data',
              icon: Hgi.arrowUpRight01,
              onPressed: () => appState.tabsController.openTable(table),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          facts.join('  ·  '),
          style: AppTheme.ui(
            size: 12.5,
            weight: FontWeight.w400,
            color: AppColors.textSecondary,
            letterSpacing: 0,
          ),
        ),
        if (comment != null && comment.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            comment,
            style: AppTheme.ui(
              size: 13.5,
              weight: FontWeight.w400,
              color: AppColors.textPrimary,
              letterSpacing: 0,
            ).copyWith(height: 1.5),
          ),
        ],
        if (explanation != null) ...[
          const SizedBox(height: 10),
          Text(
            explanation,
            style: AppTheme.ui(
              size: 12.5,
              weight: FontWeight.w400,
              color: AppColors.textMuted,
              letterSpacing: 0,
            ).copyWith(height: 1.5),
          ),
        ],
      ],
    );
  }
}

class _ColumnRow extends StatelessWidget {
  const _ColumnRow({
    required this.column,
    required this.plain,
    required this.unique,
    required this.link,
  });

  final DbColumn column;
  final String plain;
  final bool unique;
  final DbForeignKey? link;

  @override
  Widget build(BuildContext context) {
    final link = this.link;
    final tags = <(String, Color)>[
      if (column.isPrimaryKey) ('Identifies each row', AppColors.accent),
      if (unique) ('Never repeats', AppColors.info),
      if (link != null)
        ('Points to ${plainName(link.refTable)}', AppColors.tFk),
      column.nullable
          ? ('Optional', AppColors.textMuted)
          : ('Required', AppColors.textSecondary),
      if (column.hasDefault) ('Filled in if left empty', AppColors.textMuted),
    ];
    final comment = column.comment;
    return ArticleRow(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(
                width: 200,
                child: Text(
                  column.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono(
                    size: 12.5,
                    weight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  plain,
                  style: AppTheme.ui(
                    size: 12.5,
                    weight: FontWeight.w500,
                    color: AppColors.textPrimary,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                column.dataType,
                style: AppTheme.mono(size: 10.5, color: AppColors.text4),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(left: 200),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final (label, color) in tags)
                  _Tag(label: label, color: color),
              ],
            ),
          ),
          if (comment != null && comment.isNotEmpty) ...[
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.only(left: 200),
              child: Text(
                comment,
                style: AppTheme.ui(
                  size: 12,
                  weight: FontWeight.w400,
                  color: AppColors.textSecondary,
                  letterSpacing: 0,
                ).copyWith(height: 1.45),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: Radii.brSm,
      ),
      child: Text(
        label,
        style: AppTheme.ui(
          size: 10.5,
          weight: FontWeight.w500,
          color: color,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _RelationRow extends StatelessWidget {
  const _RelationRow({
    required this.icon,
    required this.sentence,
    required this.via,
    required this.target,
  });

  final IconData icon;
  final String sentence;
  final String via;

  /// The other table, when it is in the catalog — the row then opens its
  /// info page.
  final DbTable? target;

  @override
  Widget build(BuildContext context) {
    final target = this.target;
    return Hoverable(
      onTap: target == null
          ? null
          : () => appState.tabsController.openObject(
              RelationObject(target),
              view: ObjectView.info,
            ),
      cursor: target == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      builder: (context, hovering) => ArticleRow(
        highlighted: hovering && target != null,
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppColors.tFk),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: sentence),
                    TextSpan(
                      text: '  through $via',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                ),
                style: AppTheme.ui(
                  size: 12.5,
                  weight: FontWeight.w400,
                  color: AppColors.textPrimary,
                  letterSpacing: 0,
                ),
              ),
            ),
            if (target != null)
              Icon(
                Hgi.arrowRight01,
                size: 13,
                color: hovering ? AppColors.accent : AppColors.text4,
              ),
          ],
        ),
      ),
    );
  }
}

class _PlainRow extends StatelessWidget {
  const _PlainRow({required this.icon, required this.text, this.detail});

  final IconData icon;
  final String text;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return ArticleRow(
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTheme.ui(
                size: 12.5,
                weight: FontWeight.w400,
                color: AppColors.textPrimary,
                letterSpacing: 0,
              ),
            ),
          ),
          if (detail != null)
            Text(
              detail!,
              style: AppTheme.mono(size: 10.5, color: AppColors.text4),
            ),
        ],
      ),
    );
  }
}
