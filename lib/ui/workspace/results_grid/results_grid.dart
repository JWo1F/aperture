import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/cell_edit.dart';
import '../../../models/db_object.dart';
import '../../../models/order_term.dart';
import '../../../models/query_result.dart';
import '../../../models/value_format.dart';
import '../../../theme/app_theme.dart';
import '../../cell_picker/cell_picker.dart';
import '../../widgets/common.dart';
import 'cell_content.dart';
import 'cell_context_menu.dart';
import 'column_widths.dart';
import 'format_cache.dart';
import 'grid_cell.dart';
import 'grid_metrics.dart';
import 'grid_row.dart';
import 'grid_selection.dart';
import 'grid_slots.dart';
import 'header_cell.dart';
import 'index_column.dart';
import 'selection_controller.dart';
import 'tsv.dart';

/// Scrollable data grid for a [QueryResult]. Lazy body, type-aware cell
/// colours, JSON-inline highlighting, and a right-click context menu.
///
/// The grid is a thin coordinator: selection, column widths, slot mapping, and
/// cell formatting each live in their own module under `results_grid/`. This
/// widget owns the scroll controllers, the build tree, and the pointer/keyboard
/// plumbing that bridges gestures into those modules.
class ResultsGrid extends StatefulWidget {
  const ResultsGrid({
    super.key,
    required this.result,
    this.editable = false,
    this.edits,
    this.onEditCell,
    this.onRevertEdit,
    this.deletedRows,
    this.inserts,
    this.onDeleteRow,
    this.onRestoreDeletedRow,
    this.onDuplicateRow,
    this.onAddRow,
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

  /// Row indexes (in [result.rows]) marked for DELETE on Apply. Rendered
  /// with a red tint + strikethrough. Right-click → Restore to undo.
  final Set<int>? deletedRows;

  /// Synthetic INSERT rows rendered after the persistent rows. Index
  /// [result.rows.length + i] in the grid maps to [inserts[i]].
  final List<PendingInsert>? inserts;

  /// Mark [row] for DELETE (persistent rows) or discard the pending
  /// insert at the virtual row index.
  final void Function(int row)? onDeleteRow;
  final void Function(int row)? onRestoreDeletedRow;

  /// Queue a duplicate of [row] as a pending insert. PK columns are
  /// stamped DEFAULT by the state layer.
  final void Function(int row)? onDuplicateRow;

  /// Queue a blank pending insert below [row] — every column DEFAULT.
  final void Function(int row)? onAddRow;
  final List<OrderTerm>? order;
  final void Function(String column)? onSortColumn;
  final void Function(String column, bool descending)? onSetSort;
  final void Function(String column, Object? value, bool not)? onAddFilter;

  /// Optional caller-owned width store, keyed by column name.
  final Map<String, double>? widths;

  /// Called after a user drag finishes (or during, throttled by the parent)
  /// with the column name and its new width. Used to persist resizes to disk.
  final void Function(String column, double width)? onWidthChanged;

  /// Single-column foreign keys keyed by local column name.
  final Map<String, DbForeignKey>? foreignKeys;
  final void Function(DbForeignKey fk, Object? value)? onFollowForeignKey;

  /// Column catalog metadata keyed by column name. Used to disable
  /// Set NULL / Set DEFAULT in the cell picker + context menu when the
  /// column's schema forbids those values.
  final Map<String, DbColumn>? columnMeta;

  /// Resolves the "owning" table for a column name (i.e. the table where this
  /// column is a PK). Used in query result grids to surface a "Find row in
  /// {table}" action.
  final DbTable? Function(String column)? findRowOwner;
  final void Function(DbTable table, String column, Object? value)? onFindRow;

  @override
  State<ResultsGrid> createState() => _ResultsGridState();
}

class _ResultsGridState extends State<ResultsGrid> {
  // The body owns horizontal scroll outright; the header reads its offset
  // through an AnimatedBuilder so it tracks every pixel of the gesture in
  // the same frame. LinkedScrollControllerGroup syncs through a microtask
  // and adds a visible one-frame lag that made trackpad scrolling feel
  // rubbery on macOS.
  final ScrollController _hBody = ScrollController();
  final ScrollController _vBody = ScrollController();
  // The index column is pinned to the left of the horizontal scroll area but
  // still tracks vertical scroll. It runs its own ListView with this follower
  // controller, mirrored against `_vBody` on every body scroll notification.
  final ScrollController _vIndex = ScrollController();

  /// Owns keyboard shortcuts (⌘C to copy, Esc to clear, arrows to navigate).
  /// Lazily takes focus on the first cell click so the toolbar text fields
  /// keep their default editing keybindings while no cell is active.
  final FocusNode _gridFocus = FocusNode(debugLabel: 'results-grid');

  final SelectionController _selection = SelectionController();
  final ColumnWidths _widths = ColumnWidths();
  final FormatCache _formatCache = FormatCache();

  /// Interleaved render order — see [buildSlots]. Callers that index by
  /// "row" address slots here, not the raw result/insert arrays.
  List<Slot> _slots = const [];

  BuildContext? _bodyCtx;

  // Excel-style hover expansion — a single overlay owned by the grid. While
  // the pointer rests on a cell the grid draws an exact clone of it, grown
  // rightward over its neighbours so the full (≤1024-char) value fits on one
  // line. The clone carries the cell's own selection / focus / edit / row
  // state so it reads as the cell itself widening, not a floating overlay.
  // One pointer-driven overlay (vs. a per-cell Tooltip, each of which spun up
  // an AnimationController on build) keeps scroll frames free of that churn.
  final OverlayPortalController _expandCtrl = OverlayPortalController();

  /// Cell currently under the pointer, or null. A [ValueNotifier] so the
  /// overlay child rebuilds on hover changes without rebuilding the grid.
  final ValueNotifier<(int, int)?> _hoverCell = ValueNotifier(null);

  int? get _selRow => _selection.value.focus?.$1;

  int? get _selCol => _selection.value.focus?.$2;

  int get _persistentRowCount => widget.result.rows.length;

  int get _totalRowCount => _slots.length;

  @override
  void initState() {
    super.initState();
    _syncWidths();
    _syncSlots();
  }

  @override
  void didUpdateWidget(ResultsGrid old) {
    super.didUpdateWidget(old);
    // A new result set invalidates the format cache, the persistent
    // selection, and any in-progress drag. Clear them *before* re-syncing
    // widths — _syncWidths primes the format cache for sample rows in the
    // new result, so a post-sync clear would throw that work away.
    final resultChanged = !identical(old.result, widget.result);
    if (resultChanged) {
      _selection.reset();
      _formatCache.clear();
      _dismissExpansion();
    }
    if (!_widths.matches(widget.result.columns) || resultChanged) {
      _syncWidths();
    }
    // Inserts/deletes don't shift the format cache (keyed by source row) but
    // they do change slot → source mapping, so re-derive on every update.
    _syncSlots();
  }

  @override
  void dispose() {
    _hoverCell.dispose();
    _hBody.dispose();
    _vBody.dispose();
    _vIndex.dispose();
    _gridFocus.dispose();
    _widths.dispose();
    _selection.dispose();
    super.dispose();
  }

  void _syncWidths() {
    _widths.sync(
      columns: widget.result.columns,
      rows: widget.result.rows,
      saved: widget.widths,
      formatCache: _formatCache,
      columnMeta: widget.columnMeta,
      foreignKeys: widget.foreignKeys,
      sortable: widget.onSortColumn != null,
    );
  }

  void _syncSlots() {
    _slots = buildSlots(_persistentRowCount, widget.inserts);
  }

  // --- slot helpers ----------------------------------------------------

  bool _isInsertRow(int row) => _slots[row].isInsert;

  bool _isDeletedRow(int row) {
    final slot = _slots[row];
    if (slot.isInsert) return false;
    return widget.deletedRows?.contains(slot.sourceIdx) ?? false;
  }

  /// Translates a slot row index to the row index that the state layer
  /// expects in its callbacks (persistent → original row index; insert →
  /// `persistentRowCount + insertIdx`).
  int _stateRowFor(int row) {
    final slot = _slots[row];
    return slot.isInsert
        ? _persistentRowCount + slot.sourceIdx
        : slot.sourceIdx;
  }

  /// Effective edit for a cell — pending insert values for virtual rows,
  /// the [ResultsGrid.edits] map for persistent rows.
  CellEditValue? _pendingFor(int row, int column) {
    final slot = _slots[row];
    if (slot.isInsert) {
      final inserts = widget.inserts;
      if (inserts == null || slot.sourceIdx >= inserts.length) return null;
      return inserts[slot.sourceIdx].values[widget.result.columns[column]];
    }
    return widget.edits?[CellEdit(slot.sourceIdx, column)];
  }

  /// Raw DB value at a slot cell — null for pending-insert rows, which have
  /// no persistent backing row. Insert-row callers ignore the original
  /// anyway, so resolving it through the slot avoids indexing `result.rows`
  /// with a slot index that runs past the persistent rows.
  Object? _originalAt(int row, int column) {
    final slot = _slots[row];
    return slot.isInsert ? null : widget.result.rows[slot.sourceIdx][column];
  }

  // --- clipboard text --------------------------------------------------

  /// Textual form of the focus cell — pending edit wins over the original,
  /// mirroring what's painted in the grid.
  String _selectedCellText() {
    final focus = _selection.value.focus!;
    return _cellTextAt(focus.$1, focus.$2);
  }

  String _cellTextAt(int row, int column) {
    final pending = _pendingFor(row, column);
    if (pending is CellLiteral) return pending.value ?? 'NULL';
    if (pending is CellDefault) return 'DEFAULT';
    final slot = _slots[row];
    if (slot.isInsert) return 'NULL';
    return formatCellValue(widget.result.rows[slot.sourceIdx][column]) ??
        'NULL';
  }

  // --- keyboard --------------------------------------------------------

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_selection.value.isEmpty) return KeyEventResult.ignored;
      _selection.clear();
      return KeyEventResult.handled;
    }
    final isCopyChord = key == LogicalKeyboardKey.keyC &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed);
    if (isCopyChord && !_selection.value.isEmpty) {
      final sel = _selection.value;
      final singleCell = sel.ranges.length == 1 &&
          sel.ranges.first.r0 == sel.ranges.first.r1 &&
          sel.ranges.first.c0 == sel.ranges.first.c1;
      final text = singleCell
          ? _selectedCellText()
          : selectionToTsv(sel, _cellTextAt);
      Clipboard.setData(ClipboardData(text: text));
      return KeyEventResult.handled;
    }

    final moved = _selection.moveBy(
      key,
      rows: _totalRowCount,
      cols: widget.result.columns.length,
    );
    if (moved != null) {
      _scrollToCell(moved.$1, moved.$2);
      return KeyEventResult.handled;
    }

    if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.f2) &&
        widget.editable &&
        widget.onEditCell != null &&
        _selRow != null &&
        _selCol != null &&
        _bodyCtx != null) {
      _openCellPicker(
        _bodyCtx!,
        _selRow!,
        _selCol!,
        _originalAt(_selRow!, _selCol!),
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Nudge the body scrollers so the cell sits inside the viewport. We
  /// scroll only when the cell is off-screen — no jitter on every arrow.
  void _scrollToCell(int row, int col) {
    if (_vBody.hasClients) {
      final top = row * kRowHeight;
      final bottom = top + kRowHeight;
      final viewport = _vBody.position.viewportDimension;
      final offset = _vBody.offset;
      if (top < offset) {
        _vBody.jumpTo(top);
      } else if (bottom > offset + viewport) {
        _vBody.jumpTo(bottom - viewport);
      }
    }
    if (_hBody.hasClients) {
      final left = _widths.offsetOf(col);
      final right = left + _widths[col];
      final viewport = _hBody.position.viewportDimension;
      final offset = _hBody.offset;
      if (left < offset) {
        _hBody.jumpTo(math.max(0, left));
      } else if (right > offset + viewport) {
        _hBody.jumpTo(right - viewport);
      }
    }
  }

  // --- cell hit-testing & geometry -------------------------------------

  /// Maps a local-position pointer event on the body Listener to its cell.
  /// Returns `null` for clicks outside the grid.
  (int, int)? _cellAt(Offset localPos) {
    if (localPos.dx < 0) return null;
    var x = 0.0;
    int? col;
    for (var c = 0; c < _widths.length; c++) {
      final next = x + _widths[c];
      if (localPos.dx < next) {
        col = c;
        break;
      }
      x = next;
    }
    if (col == null) return null;

    final contentY = localPos.dy + (_vBody.hasClients ? _vBody.offset : 0);
    if (contentY < 0) return null;
    final row = (contentY / kRowHeight).floor();
    if (row < 0 || row >= _totalRowCount) return null;

    return (row, col);
  }

  /// Computes a cell's current global Rect from the body's RenderBox plus
  /// column/row geometry — used as the picker overlay's anchor.
  Rect _cellRect(BuildContext bodyCtx, int row, int col) {
    final box = bodyCtx.findRenderObject();
    if (box is! RenderBox) return Rect.zero;
    final origin = box.localToGlobal(Offset.zero);
    final contentX = _widths.offsetOf(col);
    final viewportY =
        row * kRowHeight - (_vBody.hasClients ? _vBody.offset : 0);
    return Rect.fromLTWH(
      origin.dx + contentX,
      origin.dy + viewportY,
      _widths[col],
      kRowHeight,
    );
  }

  // --- hover expansion -------------------------------------------------

  /// Pointer moved within the grid body — point the expansion at the cell
  /// now under the cursor, or hide it on a miss. Re-entering the same cell
  /// is a cheap no-op so ordinary mouse movement does no work.
  ///
  /// Hit-testing keys on the cell's *own* rect: the expansion is
  /// `IgnorePointer`, so once the pointer drifts past the source cell into
  /// the expanded region — which sits over a neighbour's rect — this fires
  /// for that neighbour. The expansion follows the cell genuinely hovered.
  void _handleCellHover(Offset localPos) {
    final cell = _cellAt(localPos);
    if (cell == _hoverCell.value) return;
    _hoverCell.value = cell;
    if (cell == null) {
      _expandCtrl.hide();
    } else if (!_expandCtrl.isShowing) {
      _expandCtrl.show();
    }
  }

  void _dismissExpansion() {
    _hoverCell.value = null;
    if (_expandCtrl.isShowing) _expandCtrl.hide();
  }

  /// The expansion overlay child. Rebuilds on hover changes (via [_hoverCell])
  /// and on selection changes (via [_selection]) so a click that selects the
  /// hovered cell repaints the expansion in its new selected state.
  Widget _buildExpansion(BuildContext context) {
    return ValueListenableBuilder<(int, int)?>(
      valueListenable: _hoverCell,
      builder: (context, cell, _) {
        final bodyCtx = _bodyCtx;
        if (cell == null || bodyCtx == null) return const SizedBox.shrink();
        return ValueListenableBuilder<GridSelection>(
          valueListenable: _selection,
          builder: (context, sel, _) =>
              _expansionCell(bodyCtx, cell.$1, cell.$2, sel),
        );
      },
    );
  }

  /// An exact clone of the hovered cell, grown rightward so its full value
  /// fits on one line. Width spans from the value's natural width (min: the
  /// column) up to the data viewport's right edge. The visual contract —
  /// row-fill blend, edit decoration, focus ring, deleted-row dimming — is
  /// shared with [GridRow] through [GridCell].
  Widget _expansionCell(
    BuildContext bodyCtx,
    int row,
    int column,
    GridSelection sel,
  ) {
    final rect = _cellRect(bodyCtx, row, column);
    final colWidth = _widths[column];
    // Cap: the distance from the cell's left edge to the viewport's right.
    final double maxWidth;
    if (_hBody.hasClients) {
      final toRight = _hBody.position.viewportDimension -
          _widths.offsetOf(column) +
          _hBody.offset;
      maxWidth = math.max(toRight, colWidth);
    } else {
      maxWidth = colWidth;
    }

    final slot = _slots[row];
    final isInsert = slot.isInsert;
    final isDeleted = _isDeletedRow(row);
    final pending = _pendingFor(row, column);

    return Positioned(
      left: rect.left,
      top: rect.top,
      child: IgnorePointer(
        child: GridCell(
          width: colWidth,
          maxWidth: maxWidth,
          isInsert: isInsert,
          isDeleted: isDeleted,
          isEdited: pending != null && !isInsert,
          // The expansion is standalone — it paints the row's hover/selection
          // tints itself (hovered by definition) and pre-blends them over an
          // opaque grid bg so they don't vanish into whatever sits behind.
          isHovered: true,
          isRowSelected: sel.rowSegments(row).isNotEmpty,
          isSelected: sel.contains(row, column),
          isFocus: sel.focus == (row, column),
          backdrop: AppColors.bg,
          bottomBorder: true,
          content: gridCellSpan(
            pending: pending,
            isInsert: isInsert,
            sourceIdx: slot.sourceIdx,
            column: column,
            original: _originalAt(row, column),
            formatCache: _formatCache,
            dataType:
                widget.columnMeta?[widget.result.columns[column]]?.dataType,
            maxChars: kExpandedMaxChars,
          ),
        ),
      ),
    );
  }

  // --- cell picker -----------------------------------------------------

  void _openCellPicker(
    BuildContext bodyCtx,
    int row,
    int column,
    Object? original,
  ) {
    if (widget.onEditCell == null) return;
    if (_isDeletedRow(row)) return;

    final columnName = widget.result.columns[column];
    final meta = widget.columnMeta?[columnName];
    final isInsert = _isInsertRow(row);
    final pending = _pendingFor(row, column);

    showCellPicker(
      bodyCtx,
      anchorRect: _cellRect(bodyCtx, row, column),
      target: CellEditTarget(
        columnName: columnName,
        // Insert rows have no DB-side original — type detection falls back
        // on columnDataType.
        originalValue: isInsert ? null : original,
        pendingEdit: pending,
        canBeNull: meta?.nullable ?? true,
        hasDefault: meta?.hasDefault ?? false,
        columnDataType: meta?.dataType,
      ),
      onCommit: (value) =>
          widget.onEditCell!(_stateRowFor(row), column, value),
      // Insert-row cells don't have a "revert to original" — the row itself
      // is the pending operation. Use Delete row to discard it.
      onRevert: (isInsert || pending == null)
          ? null
          : () => widget.onRevertEdit?.call(_stateRowFor(row), column),
    );
  }

  // --- context menu ----------------------------------------------------

  void _openCellMenu(
    BuildContext bodyCtx,
    Offset pos,
    int row,
    int column,
    Object? original,
  ) {
    final columnName = widget.result.columns[column];
    final isInsert = _isInsertRow(row);
    final isDeleted = _isDeletedRow(row);
    final pending = _pendingFor(row, column);
    final fk = widget.foreignKeys?[columnName];
    final owner = widget.findRowOwner?.call(columnName);
    final stateRow = _stateRowFor(row);
    final canMutateCell =
        widget.editable && widget.onEditCell != null && !isDeleted;

    showCellContextMenu(
      context,
      position: pos,
      target: CellMenuTarget(
        columnName: columnName,
        original: original,
        isInsert: isInsert,
        isDeleted: isDeleted,
        pending: pending,
        meta: widget.columnMeta?[columnName],
        foreignKey: fk,
        findRowOwner: owner,
        editable: widget.editable,
      ),
      actions: CellMenuActions(
        onOpenEditor: canMutateCell
            ? () => _openCellPicker(bodyCtx, row, column, original)
            : null,
        onSetValue: canMutateCell
            ? (value) => widget.onEditCell!(stateRow, column, value)
            : null,
        onRevert: (!isInsert && pending != null && widget.onRevertEdit != null)
            ? () => widget.onRevertEdit!(stateRow, column)
            : null,
        onDeleteRow: widget.onDeleteRow != null
            ? () => widget.onDeleteRow!(stateRow)
            : null,
        onRestoreRow: widget.onRestoreDeletedRow != null
            ? () => widget.onRestoreDeletedRow!(stateRow)
            : null,
        onDuplicateRow: widget.onDuplicateRow != null
            ? () => widget.onDuplicateRow!(stateRow)
            : null,
        onAddRow: widget.onAddRow != null
            ? () => widget.onAddRow!(stateRow)
            : null,
        onFollowForeignKey: (fk != null && widget.onFollowForeignKey != null)
            ? () => widget.onFollowForeignKey!(fk, original)
            : null,
        onFindRow: (owner != null && widget.onFindRow != null)
            ? () => widget.onFindRow!(owner, columnName, original)
            : null,
        onAddFilter: widget.onAddFilter != null
            ? (not) => widget.onAddFilter!(columnName, original, not)
            : null,
        onSetSort: widget.onSetSort != null
            ? (desc) => widget.onSetSort!(columnName, desc)
            : null,
      ),
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

    final dataWidth = _widths.total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(result.columns, dataWidth),
        Expanded(
          child: _totalRowCount == 0
              ? const EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'No rows',
                  message: 'This query returned an empty result set.',
                )
              : _buildBody(result, dataWidth),
        ),
      ],
    );
  }

  Widget _buildHeader(List<String> columns, double dataWidth) {
    final dataHeaderRow = SizedBox(
      width: dataWidth,
      child: Row(
        children: [
          for (var i = 0; i < columns.length; i++)
            HeaderCell(
              label: columns[i],
              width: _widths[i],
              sort: _sortFor(columns[i]),
              sortPriority: _sortPriority(columns[i]),
              meta: widget.columnMeta?[columns[i]],
              foreignKey: widget.foreignKeys?[columns[i]],
              onSort: widget.onSortColumn == null
                  ? null
                  : () => widget.onSortColumn!(columns[i]),
              onResize: (delta) {
                setState(() => _widths.resize(i, delta));
                final w = _widths[i];
                widget.widths?[columns[i]] = w;
                widget.onWidthChanged?.call(columns[i], w);
              },
            ),
        ],
      ),
    );

    final indexHeader = Container(
      width: kIndexWidth,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(
          right: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Text('#', style: AppTheme.mono(size: 10, color: AppColors.text4)),
    );

    // RepaintBoundary isolates the header's pixels from the body's, so a
    // header repaint (sort indicator, resize-handle hover) doesn't
    // invalidate the cells layer underneath.
    return RepaintBoundary(
      child: SizedBox(
        height: 28,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            indexHeader,
            Expanded(
              // Border sits in the foreground: each HeaderCell paints an
              // opaque bgDeep fill over the full 28px height, so a
              // background-position border would be hidden behind the cells.
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: ColoredBox(
                  color: AppColors.bgDeep,
                  // ClipRect alone would force the header row to fit the
                  // viewport. OverflowBox grants it the same unbounded
                  // horizontal space the body's scroll view has, so the Row
                  // lays out at `dataWidth` and we translate it sideways to
                  // mirror the body's scroll offset.
                  child: ClipRect(
                    child: AnimatedBuilder(
                      animation: _hBody,
                      builder: (_, child) {
                        final offset = _hBody.hasClients ? _hBody.offset : 0.0;
                        return OverflowBox(
                          minWidth: 0,
                          maxWidth: double.infinity,
                          alignment: Alignment.topLeft,
                          child: Transform.translate(
                            offset: Offset(-offset, 0),
                            child: child,
                          ),
                        );
                      },
                      child: dataHeaderRow,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(QueryResult result, double dataWidth) {
    // Suppress Material's auto-injected desktop scrollbars — we draw our own
    // via the outer Scrollbar wrappers. Inheriting platform scroll physics
    // makes the trackpad feel match other macOS apps.
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IndexColumn(
                  controller: _vIndex,
                  slots: _slots,
                  deletedRows: widget.deletedRows,
                  selection: _selection,
                ),
                Expanded(child: _buildDataArea(result, dataWidth)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDataArea(QueryResult result, double dataWidth) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bodyWidth = dataWidth < constraints.maxWidth
            ? constraints.maxWidth
            : dataWidth;
        return OverlayPortal(
          controller: _expandCtrl,
          overlayChildBuilder: _buildExpansion,
          child: RepaintBoundary(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                // Any scroll slides cells out from under the cursor — drop the
                // hover expansion rather than leave it anchored to a stale
                // position.
                _dismissExpansion();
                if (n.metrics.axis == Axis.vertical && _vIndex.hasClients) {
                  final target = _vBody.hasClients ? _vBody.offset : 0.0;
                  if ((_vIndex.position.pixels - target).abs() > 0.01) {
                    _vIndex.jumpTo(
                      target.clamp(
                        _vIndex.position.minScrollExtent,
                        _vIndex.position.maxScrollExtent,
                      ),
                    );
                  }
                }
                return false;
              },
              child: SingleChildScrollView(
                controller: _hBody,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: bodyWidth,
                  child: Builder(
                    builder: (bodyCtx) {
                      _bodyCtx = bodyCtx;
                      return MouseRegion(
                        onHover: (e) => _handleCellHover(e.localPosition),
                        onExit: (_) => _dismissExpansion(),
                        child: Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerDown: (e) {
                            // The expansion is left up — a click selects the
                            // cell, it shouldn't collapse back to one column.
                            final cell = _cellAt(e.localPosition);
                            if (cell == null) return;
                            _selection.beginPointer(cell.$1, cell.$2);
                            if (!_gridFocus.hasFocus) {
                              _gridFocus.requestFocus();
                            }
                          },
                          onPointerMove: (e) {
                            if (!_selection.isDragging) return;
                            final cell = _cellAt(e.localPosition);
                            if (cell == null) return;
                            _selection.extendDrag(cell.$1, cell.$2);
                          },
                          onPointerUp: (_) => _selection.endDrag(),
                          onPointerCancel: (_) => _selection.endDrag(),
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onDoubleTapDown: widget.editable
                                ? (d) {
                                    final cell = _cellAt(d.localPosition);
                                    if (cell == null) return;
                                    final (r, c) = cell;
                                    _openCellPicker(
                                      bodyCtx,
                                      r,
                                      c,
                                      _originalAt(r, c),
                                    );
                                  }
                                : null,
                            onSecondaryTapDown: (d) {
                              final cell = _cellAt(d.localPosition);
                              if (cell == null) return;
                              final (r, c) = cell;
                              if (!_selection.value.contains(r, c)) {
                                _selection.selectCell(r, c);
                                if (!_gridFocus.hasFocus) {
                                  _gridFocus.requestFocus();
                                }
                              }
                              _openCellMenu(
                                bodyCtx,
                                d.globalPosition,
                                r,
                                c,
                                _originalAt(r, c),
                              );
                            },
                            child: ListView.builder(
                              controller: _vBody,
                              itemCount: _totalRowCount,
                              itemExtent: kRowHeight,
                              // Rows hold no local state (selection lives in
                              // a ValueNotifier). Skipping per-child
                              // keepalives saves a widget allocation per row
                              // scrolled in.
                              addAutomaticKeepAlives: false,
                              itemBuilder: (_, r) {
                                final slot = _slots[r];
                                final values = slot.isInsert
                                    ? const <Object?>[]
                                    : result.rows[slot.sourceIdx];
                                return GridRow(
                                  row: r,
                                  sourceIdx: slot.sourceIdx,
                                  isInsert: slot.isInsert,
                                  isDeleted: _isDeletedRow(r),
                                  values: values,
                                  rowWidth: bodyWidth,
                                  columns: result.columns,
                                  columnMeta: widget.columnMeta,
                                  widths: _widths,
                                  selection: _selection,
                                  pendingFor: (col) => _pendingFor(r, col),
                                  formatCache: _formatCache,
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
