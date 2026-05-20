import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:linked_scroll_controller/linked_scroll_controller.dart';

import '../../models/db_object.dart';
import '../../models/order_term.dart';
import '../../models/query_result.dart';
import '../../models/value_format.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../cell_picker/cell_picker.dart';
import '../widgets/common.dart';
import '../widgets/context_menu.dart';
import '../widgets/json_spans.dart';

/// Scrollable data grid for a [QueryResult]. Lazy body, type-aware cell
/// colours, JSON-inline highlighting, and a right-click context menu.
class ResultsGrid extends StatefulWidget {
  const ResultsGrid({
    super.key,
    required this.result,
    this.editable = false,
    this.edits,
    this.onEditCell,
    this.onRevertEdit,
    this.order,
    this.onSortColumn,
    this.onSetSort,
    this.onAddFilter,
    this.widths,
    this.onWidthChanged,
    this.foreignKeys,
    this.onFollowForeignKey,
    this.columnMeta,
    this.findRowOwner,
    this.onFindRow,
  });

  final QueryResult result;
  final bool editable;
  final Map<CellEdit, CellEditValue>? edits;
  final void Function(int row, int column, CellEditValue value)? onEditCell;
  final void Function(int row, int column)? onRevertEdit;
  final List<OrderTerm>? order;
  final void Function(String column)? onSortColumn;
  final void Function(String column, bool descending)? onSetSort;
  final void Function(String column, dynamic value, bool not)? onAddFilter;

  /// Optional caller-owned width store, keyed by column name.
  final Map<String, double>? widths;

  /// Called after a user drag finishes (or during, throttled by the parent)
  /// with the column name and its new width. Used to persist resizes to disk.
  final void Function(String column, double width)? onWidthChanged;

  /// Single-column foreign keys keyed by local column name.
  final Map<String, DbForeignKey>? foreignKeys;
  final void Function(DbForeignKey fk, dynamic value)? onFollowForeignKey;

  /// Column catalog metadata keyed by column name. Used to disable
  /// Set NULL / Set DEFAULT in the cell picker + context menu when the
  /// column's schema forbids those values.
  final Map<String, DbColumn>? columnMeta;

  /// Resolves the "owning" table for a column name (i.e. the table where this
  /// column is a PK). Used in query result grids to surface a "Find row in
  /// {table}" action.
  final DbTable? Function(String column)? findRowOwner;
  final void Function(DbTable table, String column, dynamic value)?
      onFindRow;

  @override
  State<ResultsGrid> createState() => _ResultsGridState();
}

class _ResultsGridState extends State<ResultsGrid> {
  static const double _rowHeight = 28;
  static const double _indexWidth = 56;
  static const double _handleWidth = 7;

  late final LinkedScrollControllerGroup _hGroup;
  late final ScrollController _hHeader;
  late final ScrollController _hBody;
  final ScrollController _vBody = ScrollController();

  /// Focus node for the grid body — owns keyboard shortcuts (⌘C / Ctrl-C
  /// to copy the selected cell, Esc to clear the selection). Lazily takes
  /// focus on the first cell click so the toolbar text fields keep their
  /// default editing keybindings while no cell is active.
  final FocusNode _gridFocus = FocusNode(debugLabel: 'results-grid');

  /// The active cell (row, column). `null` until the user clicks one; cleared
  /// by Esc or when the underlying result changes (new page / filter).
  int? _selRow;
  int? _selCol;

  List<double> _widths = [];
  List<String> _widthKeys = [];

  final TextStyle _baseText = AppTheme.mono(size: 11.5);
  final TextStyle _nullText = AppTheme.mono(
    size: 11.5,
    color: AppColors.textMuted,
  ).copyWith(fontStyle: FontStyle.italic);

  // Reused across all width measurements to avoid per-cell allocation.
  final TextPainter _measurer =
      TextPainter(textDirection: TextDirection.ltr, maxLines: 1);

  static const double _autoMin = 64;
  static const double _autoMax = 200;
  static const double _cellPad = 20; // 9px each side + 2 fudge
  static const double _headerExtra = 28; // sort icon + spacing + resize handle

  @override
  void initState() {
    super.initState();
    _hGroup = LinkedScrollControllerGroup();
    _hHeader = _hGroup.addAndGet();
    _hBody = _hGroup.addAndGet();
    _syncWidths();
  }

  @override
  void didUpdateWidget(ResultsGrid old) {
    super.didUpdateWidget(old);
    if (!_sameColumns(widget.result.columns, _widthKeys)) {
      _syncWidths();
    } else if (!identical(old.result, widget.result)) {
      _syncWidths();
    }
    // A new result set invalidates the row/column indices we held; clearing
    // the selection avoids highlighting an arbitrary cell after pagination.
    if (!identical(old.result, widget.result)) {
      _selRow = null;
      _selCol = null;
    }
  }

  bool _sameColumns(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Default width = widest visible cell (and the header) in this column,
  /// clamped between [_autoMin] and [_autoMax]. Cells already ellipsize, so
  /// we measure at most the first 200 chars of each value to keep this cheap.
  double _autoWidth(String column, int columnIndex) {
    final headerStyle = AppTheme.mono(
      size: 11.5,
      weight: FontWeight.w600,
    );

    _measurer
      ..text = TextSpan(text: column, style: headerStyle)
      ..layout();
    var widest = _measurer.width + _headerExtra;

    for (final row in widget.result.rows) {
      final raw = row[columnIndex];
      final formatted = formatCellValue(raw);
      final text = formatted ?? 'NULL';
      final sample = text.length > 200 ? text.substring(0, 200) : text;
      _measurer
        ..text = TextSpan(text: sample, style: _baseText)
        ..layout();
      final w = _measurer.width + _cellPad;
      if (w > widest) widest = w;
    }

    return widest.clamp(_autoMin, _autoMax);
  }

  void _syncWidths() {
    _widthKeys = List.of(widget.result.columns);
    final saved = widget.widths;
    _widths = [
      for (var i = 0; i < widget.result.columns.length; i++)
        saved?[widget.result.columns[i]] ??
            _autoWidth(widget.result.columns[i], i),
    ];
  }

  @override
  void dispose() {
    _hHeader.dispose();
    _hBody.dispose();
    _vBody.dispose();
    _gridFocus.dispose();
    _measurer.dispose();
    super.dispose();
  }

  // --- selection -------------------------------------------------------

  void _selectCell(int row, int column) {
    setState(() {
      _selRow = row;
      _selCol = column;
    });
    _gridFocus.requestFocus();
  }

  void _clearSelection() {
    if (_selRow == null && _selCol == null) return;
    setState(() {
      _selRow = null;
      _selCol = null;
    });
  }

  /// Returns the textual form of the selected cell — pending edit (if any)
  /// wins over the original, mirroring what's painted in the grid.
  String _selectedCellText() {
    final r = _selRow!;
    final c = _selCol!;
    final pending = widget.edits?[CellEdit(r, c)];
    if (pending is CellLiteral) return pending.value ?? 'NULL';
    if (pending is CellDefault) return 'DEFAULT';
    final formatted = formatCellValue(widget.result.rows[r][c]);
    return formatted ?? 'NULL';
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_selRow == null) return KeyEventResult.ignored;
      _clearSelection();
      return KeyEventResult.handled;
    }
    final isCopyChord = event.logicalKey == LogicalKeyboardKey.keyC &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed);
    if (isCopyChord && _selRow != null && _selCol != null) {
      Clipboard.setData(ClipboardData(text: _selectedCellText()));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // --- cell picker -----------------------------------------------------

  void _openCellPicker(
    BuildContext cellCtx,
    int row,
    int column,
    dynamic original,
  ) {
    if (widget.onEditCell == null) return;
    final renderObject = cellCtx.findRenderObject();
    if (renderObject is! RenderBox) return;
    final origin = renderObject.localToGlobal(Offset.zero);
    final size = renderObject.size;
    final rect =
        Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height);

    final columnName = widget.result.columns[column];
    final key = CellEdit(row, column);
    final pending = widget.edits?[key];
    final meta = widget.columnMeta?[columnName];

    showCellPicker(
      cellCtx,
      anchorRect: rect,
      columnName: columnName,
      originalValue: original,
      pendingEdit: pending,
      canBeNull: meta?.nullable ?? true,
      hasDefault: meta?.hasDefault ?? false,
      columnDataType: meta?.dataType,
      onCommit: (value) => widget.onEditCell!(row, column, value),
      onRevert: pending == null
          ? null
          : () => widget.onRevertEdit?.call(row, column),
    );
  }

  // --- sort lookup -----------------------------------------------------

  OrderTerm? _sortFor(String column) {
    for (final term in widget.order ?? const <OrderTerm>[]) {
      if (term.column == column) return term;
    }
    return null;
  }

  int _sortPriority(String column) {
    final order = widget.order ?? const <OrderTerm>[];
    if (order.length < 2) return 0;
    final index = order.indexWhere((t) => t.column == column);
    return index == -1 ? 0 : index + 1;
  }

  // --- type colour -----------------------------------------------------

  Color _colorFor(dynamic value) {
    if (value is bool) return AppColors.sqlFunction;
    if (value is num || value is BigInt) return AppColors.sqlNumber;
    if (value is DateTime) return AppColors.info;
    if (value is Map || value is List) return AppColors.sqlString;
    return AppColors.textPrimary;
  }

  bool _wantsTooltip(dynamic original, String text) {
    if (original is Map || original is List) return true;
    if (text.length > 36) return true;
    return false;
  }

  // --- context menu ----------------------------------------------------

  void _openCellMenu(
    BuildContext cellCtx,
    Offset pos,
    int row,
    int column,
    dynamic original,
  ) {
    final columnName = widget.result.columns[column];
    final key = CellEdit(row, column);
    final pending = widget.edits?[key];
    final isEdited = pending != null;
    final meta = widget.columnMeta?[columnName];
    final canBeNull = meta?.nullable ?? true;
    final hasDefault = meta?.hasDefault ?? false;

    final String? displayValue = pending is CellLiteral
        ? pending.value
        : (pending is CellDefault ? null : formatCellValue(original));

    void copy(String text) =>
        Clipboard.setData(ClipboardData(text: text));

    final findOwner = widget.findRowOwner?.call(columnName);

    final entries = <CmEntry>[
      CmItem(
        icon: Icons.copy,
        label: 'Copy value',
        shortcut: '⌘C',
        onTap: () => copy(displayValue ?? 'NULL'),
      ),
      if (original is Map || original is List)
        CmItem(
          icon: Icons.data_object,
          label: 'Copy pretty JSON',
          onTap: () {
            try {
              copy(const JsonEncoder.withIndent('  ').convert(original));
            } catch (_) {}
          },
        ),
      CmItem(
        icon: Icons.label_outline,
        label: 'Copy column name',
        onTap: () => copy(columnName),
      ),
      CmItem(
        icon: Icons.format_align_left,
        label: 'Copy as "$columnName = …"',
        onTap: () => copy('$columnName = ${displayValue ?? 'NULL'}'),
      ),
      const CmDivider(),
      if (widget.foreignKeys?[columnName] != null &&
          widget.onFollowForeignKey != null) ...[
        CmItem(
          icon: Icons.north_east,
          label: 'Follow → ${widget.foreignKeys![columnName]!.refQualified}',
          onTap: () => widget.onFollowForeignKey!(
            widget.foreignKeys![columnName]!,
            original,
          ),
        ),
        const CmDivider(),
      ],
      if (findOwner != null && widget.onFindRow != null) ...[
        CmItem(
          icon: Icons.search,
          label: 'Find row in ${findOwner.qualifiedKey}',
          onTap: () => widget.onFindRow!(findOwner, columnName, original),
        ),
        const CmDivider(),
      ],
      if (widget.editable && widget.onEditCell != null) ...[
        CmItem(
          icon: Icons.edit_outlined,
          label: 'Edit cell',
          shortcut: '⏎⏎',
          onTap: () => _openCellPicker(cellCtx, row, column, original),
        ),
        CmItem(
          icon: Icons.not_interested,
          label: canBeNull ? 'Set NULL' : 'Set NULL (column is NOT NULL)',
          enabled: canBeNull,
          onTap: () => widget.onEditCell!(
            row,
            column,
            const CellLiteral(null),
          ),
        ),
        CmItem(
          icon: Icons.settings_backup_restore,
          label: hasDefault
              ? 'Set DEFAULT'
              : 'Set DEFAULT (no default value)',
          enabled: hasDefault,
          onTap: () => widget.onEditCell!(
            row,
            column,
            const CellDefault(),
          ),
        ),
        if (isEdited && widget.onRevertEdit != null)
          CmItem(
            icon: Icons.undo,
            label: 'Revert change',
            onTap: () => widget.onRevertEdit!(row, column),
          ),
        const CmDivider(),
      ],
      if (widget.onAddFilter != null) ...[
        CmItem(
          icon: Icons.filter_alt_outlined,
          label: 'Filter: $columnName = value',
          onTap: () => widget.onAddFilter!(columnName, original, false),
        ),
        CmItem(
          icon: Icons.block,
          label: 'Filter: $columnName ≠ value',
          onTap: () => widget.onAddFilter!(columnName, original, true),
        ),
      ],
      if (widget.onSetSort != null) ...[
        CmItem(
          icon: Icons.arrow_upward,
          label: 'Sort ascending',
          onTap: () => widget.onSetSort!(columnName, false),
        ),
        CmItem(
          icon: Icons.arrow_downward,
          label: 'Sort descending',
          onTap: () => widget.onSetSort!(columnName, true),
        ),
      ],
    ];

    showContextMenu(context, globalPosition: pos, entries: entries);
  }

  // --- build -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final result = widget.result;

    if (result.isError) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Query failed',
        message: result.error,
      );
    }
    if (!result.hasColumns) {
      return EmptyState(
        icon: Icons.check_circle_outline,
        title: 'Statement executed',
        message: '${result.affectedRows ?? 0} row(s) affected.',
      );
    }

    final totalWidth =
        _indexWidth + _widths.fold<double>(0, (s, w) => s + w);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(result.columns, totalWidth),
        Expanded(
          child: result.rows.isEmpty
              ? const EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'No rows',
                  message: 'This query returned an empty result set.',
                )
              : _buildBody(result, totalWidth),
        ),
      ],
    );
  }

  Widget _buildHeader(List<String> columns, double totalWidth) {
    return Container(
      height: _rowHeight,
      decoration: const BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border(bottom: BorderSide(color: AppColors.borderStrong)),
      ),
      child: SingleChildScrollView(
        controller: _hHeader,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: SizedBox(
          width: totalWidth,
          child: Row(
            children: [
              _staticCell(
                width: _indexWidth,
                align: Alignment.center,
                child: Text('#', style: AppTheme.eyebrow()),
              ),
              for (var i = 0; i < columns.length; i++)
                _HeaderCell(
                  label: columns[i],
                  width: _widths[i],
                  handleWidth: _handleWidth,
                  sort: _sortFor(columns[i]),
                  sortPriority: _sortPriority(columns[i]),
                  isForeignKey:
                      widget.foreignKeys?.containsKey(columns[i]) ?? false,
                  onSort: widget.onSortColumn == null
                      ? null
                      : () => widget.onSortColumn!(columns[i]),
                  onResize: (delta) {
                    final next =
                        (_widths[i] + delta).clamp(64.0, 900.0);
                    setState(() => _widths[i] = next);
                    widget.widths?[columns[i]] = next;
                    widget.onWidthChanged?.call(columns[i], next);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(QueryResult result, double totalWidth) {
    // Suppress Material's auto-injected desktop scrollbars — we draw our
    // own via the outer Scrollbar wrappers, and the default behavior would
    // stack a second vertical bar against the ListView. Inheriting platform
    // scroll physics (rather than forcing Clamping) makes the trackpad feel
    // match other macOS apps.
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Scrollbar(
        controller: _vBody,
        thumbVisibility: true,
        notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
        child: Scrollbar(
          controller: _hBody,
          thumbVisibility: true,
          notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
          child: Focus(
            focusNode: _gridFocus,
            onKeyEvent: _handleKey,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Expanding to at least the viewport width keeps row stripes
                // flush to the right edge when the table is narrower than
                // its container, and collapses the redundant horizontal
                // scrollbar in that case.
                final bodyWidth = totalWidth < constraints.maxWidth
                    ? constraints.maxWidth
                    : totalWidth;
                return SingleChildScrollView(
                  controller: _hBody,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: bodyWidth,
                    child: ListView.builder(
                      controller: _vBody,
                      itemCount: result.rows.length,
                      itemExtent: _rowHeight,
                      itemBuilder: (_, r) =>
                          _buildRow(r, result.rows[r], bodyWidth),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(int row, List<dynamic> values, double rowWidth) {
    final isSelectedRow = _selRow == row;
    final Color bg;
    if (isSelectedRow) {
      // ~10% accent — visible without competing with the focused cell's
      // bolder border.
      bg = const Color(0x1A5B7CFA);
    } else if (row.isOdd) {
      bg = AppColors.surfaceAlt;
    } else {
      bg = Colors.transparent;
    }
    return Container(
      width: rowWidth,
      decoration: BoxDecoration(
        color: bg,
        border: const Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          _staticCell(
            width: _indexWidth,
            align: Alignment.centerRight,
            child: Text(
              '${row + 1}',
              style: AppTheme.mono(
                size: 10.5,
                color: isSelectedRow
                    ? AppColors.accent
                    : AppColors.textMuted,
                weight: isSelectedRow ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          for (var c = 0; c < values.length; c++)
            _buildCell(row, c, values[c]),
        ],
      ),
    );
  }

  Widget _buildCell(int row, int column, dynamic original) {
    final key = CellEdit(row, column);
    final pending = widget.edits?[key];
    final isEdited = pending != null;

    // Decide content based on the cell's effective state.
    final Widget content;
    final bool tooltipUseful;
    final String tooltipText;

    if (pending is CellDefault) {
      content = Text(
        'DEFAULT',
        style: _baseText.copyWith(
          color: AppColors.accent,
          fontWeight: FontWeight.w600,
        ),
      );
      tooltipUseful = false;
      tooltipText = 'DEFAULT';
    } else {
      final String? displayValue =
          pending is CellLiteral ? pending.value : formatCellValue(original);
      final bool isNull = displayValue == null;

      if (isNull) {
        content = Text(
          'NULL',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _nullText,
        );
        tooltipUseful = false;
        tooltipText = 'NULL';
      } else if (!isEdited && (original is Map || original is List)) {
        content = Text.rich(
          TextSpan(children: jsonSpans(displayValue, _baseText)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
        tooltipUseful = true;
        tooltipText = displayValue;
      } else {
        content = Text(
          displayValue,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _baseText.copyWith(
            color: isEdited ? AppColors.textPrimary : _colorFor(original),
          ),
        );
        tooltipUseful = _wantsTooltip(original, displayValue);
        tooltipText = displayValue;
      }
    }

    Widget rendered = content;
    if (tooltipUseful) {
      rendered = Tooltip(
        message: tooltipText,
        waitDuration: const Duration(milliseconds: 300),
        preferBelow: false,
        textStyle: AppTheme.mono(size: 11.5, color: AppColors.textPrimary),
        child: rendered,
      );
    }

    final isSelected = _selRow == row && _selCol == column;

    final cellBody = Container(
      width: _widths[column],
      height: _rowHeight,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: isEdited
          ? const BoxDecoration(
              color: AppColors.accentSoft,
              border: Border(
                left: BorderSide(color: AppColors.accent, width: 2),
              ),
            )
          : null,
      child: rendered,
    );

    // The selection ring is drawn as an overlay so it doesn't shift the
    // cell's text or interfere with the edited-state left stripe.
    final Widget cell = isSelected
        ? Stack(
            children: [
              cellBody,
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.accent,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          )
        : cellBody;

    return Builder(
      builder: (cellCtx) => MouseRegion(
        cursor: widget.editable
            ? SystemMouseCursors.text
            : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _selectCell(row, column),
          onDoubleTap: widget.editable
              ? () => _openCellPicker(cellCtx, row, column, original)
              : null,
          onSecondaryTapDown: (d) {
            _selectCell(row, column);
            _openCellMenu(
              cellCtx,
              d.globalPosition,
              row,
              column,
              original,
            );
          },
          child: cell,
        ),
      ),
    );
  }

  Widget _staticCell({
    required double width,
    required Widget child,
    Alignment align = Alignment.centerLeft,
  }) {
    return Container(
      width: width,
      height: _rowHeight,
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      child: child,
    );
  }
}

/// A header cell: sortable label area plus a trailing drag handle for resize.
class _HeaderCell extends StatefulWidget {
  const _HeaderCell({
    required this.label,
    required this.width,
    required this.handleWidth,
    required this.onResize,
    required this.sort,
    required this.sortPriority,
    this.onSort,
    this.isForeignKey = false,
  });

  final String label;
  final double width;
  final double handleWidth;
  final ValueChanged<double> onResize;
  final OrderTerm? sort;
  final int sortPriority;
  final VoidCallback? onSort;
  final bool isForeignKey;

  @override
  State<_HeaderCell> createState() => _HeaderCellState();
}

class _HeaderCellState extends State<_HeaderCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final sort = widget.sort;
    final sortable = widget.onSort != null;

    return SizedBox(
      width: widget.width,
      height: 28,
      child: Stack(
        children: [
          MouseRegion(
            cursor: sortable
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              onTap: widget.onSort,
              child: Container(
                color: _hover && sortable
                    ? AppColors.surfaceHover
                    : Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.mono(
                          size: 11.5,
                          color: sort != null
                              ? AppColors.accent
                              : AppColors.textPrimary,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (widget.isForeignKey) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.north_east,
                        size: 10,
                        color: AppColors.info,
                      ),
                    ],
                    if (sort != null) ...[
                      const SizedBox(width: 4),
                      Icon(
                        sort.descending
                            ? Icons.arrow_downward
                            : Icons.arrow_upward,
                        size: 12,
                        color: AppColors.accent,
                      ),
                      if (widget.sortPriority > 0)
                        Text(
                          '${widget.sortPriority}',
                          style: AppTheme.mono(
                            size: 9,
                            color: AppColors.accent,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: widget.handleWidth,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (d) => widget.onResize(d.delta.dx),
                child: Center(
                  child: Container(width: 1, color: AppColors.border),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
