import 'package:flutter/material.dart';

import '../../../models/count_format.dart';
import '../../../models/db_object.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import '../../widgets/common.dart';
import '../../widgets/filter_field.dart';
import '../../widgets/table_glyph.dart';
import 'panel.dart';

enum _SortKey { name, schema, rows, size }

/// Every relation in the catalog as a filterable, sortable list. Collapsed to
/// [_collapsedLimit] rows until expanded, so a thousand-table catalog doesn't
/// build a thousand rows just to show the home screen.
class RelationsPanel extends StatefulWidget {
  const RelationsPanel({
    super.key,
    required this.relations,
    required this.schema,
    required this.onClearSchema,
    required this.onOpen,
    required this.loading,
    required this.error,
    required this.showSchemaColumn,
    required this.tint,
  });

  final List<DbTable> relations;

  /// Restricts the list to one schema, set from the schemas panel.
  final String? schema;
  final VoidCallback onClearSchema;
  final void Function(DbTable) onOpen;
  final bool loading;
  final Object? error;
  final bool showSchemaColumn;
  final Color tint;

  @override
  State<RelationsPanel> createState() => _RelationsPanelState();
}

class _RelationsPanelState extends State<RelationsPanel> {
  static const _collapsedLimit = 14;

  final _filter = TextEditingController();
  bool _expanded = false;

  /// Null until the user clicks a column header. The default follows the
  /// catalog: largest-first once sizes arrive, alphabetical before that and
  /// on engines that report none.
  _SortKey? _userSort;
  bool _userAscending = true;

  bool get _hasSizes => widget.relations.any((r) => r.sizeBytes != null);
  bool get _hasRows => widget.relations.any((r) => r.rowEstimate != null);

  _SortKey get _sort =>
      _userSort ?? (_hasSizes ? _SortKey.size : _SortKey.name);
  bool get _ascending =>
      _userSort == null ? _sort == _SortKey.name : _userAscending;

  @override
  void initState() {
    super.initState();
    _filter.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  void _toggleSort(_SortKey key) {
    setState(() {
      if (_sort == key) {
        _userAscending = !_ascending;
      } else {
        _userAscending = key == _SortKey.name || key == _SortKey.schema;
      }
      _userSort = key;
    });
  }

  List<DbTable> _visible() {
    final q = _filter.text.trim().toLowerCase();
    final list = [
      for (final r in widget.relations)
        if ((widget.schema == null || r.schema == widget.schema) &&
            (q.isEmpty || r.qualifiedKey.toLowerCase().contains(q)))
          r,
    ];
    int byName(DbTable a, DbTable b) =>
        a.qualifiedKey.compareTo(b.qualifiedKey);
    int cmp(DbTable a, DbTable b) => switch (_sort) {
      _SortKey.name => a.name.compareTo(b.name),
      _SortKey.schema => a.schema.compareTo(b.schema),
      _SortKey.rows => (a.rowEstimate ?? -1).compareTo(b.rowEstimate ?? -1),
      _SortKey.size => (a.sizeBytes ?? -1).compareTo(b.sizeBytes ?? -1),
    };
    list.sort((a, b) {
      final c = _ascending ? cmp(a, b) : cmp(b, a);
      return c != 0 ? c : byName(a, b);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible();
    final shown = _expanded ? visible : visible.take(_collapsedLimit).toList();
    final maxSize = widget.relations.fold<int>(
      0,
      (m, r) => (r.sizeBytes ?? 0) > m ? r.sizeBytes! : m,
    );

    return HomePanel(
      title: 'Relations',
      count: widget.relations.length,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.schema != null) ...[
            _SchemaChip(name: widget.schema!, onClear: widget.onClearSchema),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 200,
            child: FilterField(controller: _filter, hint: 'Filter relations…'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeaderRow(
            sort: _sort,
            ascending: _ascending,
            showSchema: widget.showSchemaColumn,
            showRows: _hasRows,
            showSize: _hasSizes,
            onSort: _toggleSort,
          ),
          if (widget.error != null && widget.relations.isEmpty)
            HomePanelEmpty(
              icon: Hgi.alertCircle,
              message: 'Catalog failed to load: ${widget.error}',
            )
          else if (widget.loading && widget.relations.isEmpty)
            const HomePanelEmpty(
              icon: Hgi.database01,
              message: 'Loading catalog…',
            )
          else if (visible.isEmpty)
            HomePanelEmpty(
              icon: Hgi.search01,
              message: widget.relations.isEmpty
                  ? 'This database has no tables or views.'
                  : 'Nothing matches the filter.',
            )
          else
            for (final t in shown)
              _RelationRow(
                table: t,
                showSchema: widget.showSchemaColumn,
                showRows: _hasRows,
                showSize: _hasSizes,
                fraction: maxSize == 0 ? 0 : (t.sizeBytes ?? 0) / maxSize,
                tint: widget.tint,
                onTap: () => widget.onOpen(t),
              ),
          if (visible.length > _collapsedLimit)
            Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                border: Border(top: BorderSide(color: AppColors.borderSoft)),
              ),
              child: Row(
                children: [
                  Text(
                    'Showing ${shown.length} of ${withCommas(visible.length)}',
                    style: AppTheme.ui(
                      size: 11,
                      weight: FontWeight.w400,
                      color: AppColors.textMuted,
                      letterSpacing: 0,
                    ),
                  ),
                  const Spacer(),
                  HomeLink(
                    label: _expanded ? 'Show fewer' : 'Show all',
                    onTap: () => setState(() => _expanded = !_expanded),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

const double _schemaWidth = 130;
const double _rowsWidth = 72;
const double _sizeWidth = 132;

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.sort,
    required this.ascending,
    required this.showSchema,
    required this.showRows,
    required this.showSize,
    required this.onSort,
  });

  final _SortKey sort;
  final bool ascending;
  final bool showSchema;
  final bool showRows;
  final bool showSize;
  final void Function(_SortKey) onSort;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, _SortKey key, {bool end = false}) {
      final active = sort == key;
      return Hoverable(
        onTap: () => onSort(key),
        builder: (context, hovering) {
          final color = active || hovering
              ? AppColors.textSecondary
              : AppColors.textMuted;
          return Row(
            mainAxisAlignment: end
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: AppTheme.eyebrow(color: color)),
              const SizedBox(width: 3),
              Icon(
                ascending ? Hgi.arrowUp01 : Hgi.arrowDown01,
                size: 11,
                color: active ? color : Colors.transparent,
              ),
            ],
          );
        },
      );
    }

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: AppColors.surfaceAlt,
      child: Row(
        children: [
          const SizedBox(width: 23),
          Expanded(child: cell('Name', _SortKey.name)),
          if (showSchema)
            SizedBox(
              width: _schemaWidth,
              child: cell('Schema', _SortKey.schema),
            ),
          if (showRows)
            SizedBox(
              width: _rowsWidth,
              child: cell('Rows', _SortKey.rows, end: true),
            ),
          if (showSize)
            SizedBox(
              width: _sizeWidth,
              child: cell('Size', _SortKey.size, end: true),
            ),
        ],
      ),
    );
  }
}

class _RelationRow extends StatelessWidget {
  const _RelationRow({
    required this.table,
    required this.showSchema,
    required this.showRows,
    required this.showSize,
    required this.fraction,
    required this.tint,
    required this.onTap,
  });

  final DbTable table;
  final bool showSchema;
  final bool showRows;
  final bool showSize;
  final double fraction;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = AppTheme.mono(size: 11, color: AppColors.textMuted);
    return HomePanelRow(
      onTap: onTap,
      height: 32,
      child: Row(
        children: [
          TableGlyph(size: 13, color: table.isView ? AppColors.tDate : tint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              table.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.mono(size: 12, color: AppColors.textPrimary),
            ),
          ),
          if (showSchema)
            SizedBox(
              width: _schemaWidth,
              child: Text(
                table.schema,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: muted,
              ),
            ),
          if (showRows)
            SizedBox(
              width: _rowsWidth,
              child: Text(
                table.rowEstimate == null
                    ? '—'
                    : compactCount(table.rowEstimate!),
                textAlign: TextAlign.end,
                style: muted,
              ),
            ),
          if (showSize)
            SizedBox(
              width: _sizeWidth,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ShareBar(
                    fraction: fraction,
                    color: tint.withValues(alpha: 0.7),
                    width: 56,
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 52,
                    child: Text(
                      table.sizeBytes == null
                          ? '—'
                          : compactBytes(table.sizeBytes!),
                      textAlign: TextAlign.end,
                      style: AppTheme.mono(
                        size: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SchemaChip extends StatelessWidget {
  const _SchemaChip({required this.name, required this.onClear});

  final String name;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onClear,
      builder: (context, hovering) => Container(
        height: 24,
        padding: const EdgeInsets.only(left: 8, right: 5),
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: Radii.brSm,
          border: Border.all(
            color: hovering ? AppColors.accent : AppColors.accentRing,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: AppTheme.mono(size: 11, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 4),
            Icon(Hgi.cancel01, size: 11, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
