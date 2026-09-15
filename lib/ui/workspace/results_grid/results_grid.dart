import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/cell_edit.dart';
import '../../../models/db_object.dart';
import '../../../models/order_term.dart';
import '../../../models/query_result.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'body_gestures.dart';
import 'cell_interaction.dart';
import 'column_widths.dart';
import 'format_cache.dart';
import 'grid_keyboard.dart';
import 'grid_metrics.dart';
import 'grid_row.dart';
import 'grid_slots.dart';
import 'header_strip.dart';
import 'hover_expansion.dart';
import 'index_column.dart';
import 'selection_controller.dart';

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
  final HoverExpansion _expansion = HoverExpansion();

  late final CellInteraction _interaction = CellInteraction(
    widget: widget,
    isInsertRow: _isInsertRow,
    isDeletedRow: _isDeletedRow,
    pendingFor: _pendingFor,
    stateRowFor: _stateRowFor,
    cellRect: _cellRect,
  );

  late final GridKeyboard _keyboard = GridKeyboard(
    widget: widget,
    selection: _selection,
    widths: _widths,
    slots: _slots,
    vBody: _vBody,
    hBody: _hBody,
    interaction: _interaction,
    bodyCtxOf: () => _bodyCtx,
  );

  /// Interleaved render order — see [buildSlots]. Callers that index by
  /// "row" address slots here, not the raw result/insert arrays.
  List<Slot> _slots = const [];

  BuildContext? _bodyCtx;

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
    _syncWidgetRefs();
    // A new result set invalidates the format cache, the persistent
    // selection, and any in-progress drag. Clear them *before* re-syncing
    // widths — _syncWidths primes the format cache for sample rows in the
    // new result, so a post-sync clear would throw that work away.
    final resultChanged = !identical(old.result, widget.result);
    if (resultChanged) {
      _selection.reset();
      _formatCache.clear();
      _expansion.dismiss();
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
    _expansion.dispose();
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
    _keyboard.slots = _slots;
  }

  /// The keyboard handler and the cell-menu dispatcher are built once and
  /// live as long as this `State`, which outlives every result the grid
  /// shows. Re-point them at the current `widget` on each update or they
  /// keep answering with the first page's rows, columns and callbacks.
  void _syncWidgetRefs() {
    _interaction.widget = widget;
    _keyboard.widget = widget;
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

  /// Hit-testing keys on the cell's *own* rect: the expansion is
  /// `IgnorePointer`, so once the pointer drifts past the source cell into
  /// the expanded region — which sits over a neighbour's rect — this fires
  /// for that neighbour. The expansion follows the cell genuinely hovered.
  void _handleCellHover(Offset localPos) {
    _expansion.update(_cellAt(localPos));
  }

  ExpansionContext? _expansionContext() {
    final bodyCtx = _bodyCtx;
    if (bodyCtx == null) return null;
    return ExpansionContext(
      bodyCtx: bodyCtx,
      slots: _slots,
      widths: _widths,
      formatCache: _formatCache,
      columns: widget.result.columns,
      columnMeta: widget.columnMeta,
      deletedRows: widget.deletedRows,
      inserts: widget.inserts,
      edits: widget.edits,
      rows: widget.result.rows,
      vBody: _vBody,
      hBody: _hBody,
    );
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeaderStrip(
          columns: result.columns,
          widths: _widths,
          hBody: _hBody,
          columnMeta: widget.columnMeta,
          foreignKeys: widget.foreignKeys,
          order: widget.order,
          onSortColumn: widget.onSortColumn,
          savedWidths: widget.widths,
          onWidthChanged: widget.onWidthChanged,
        ),
        Expanded(
          child: _totalRowCount == 0
              ? const EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'No rows',
                  message: 'This query returned an empty result set.',
                )
              : _buildBody(result),
        ),
      ],
    );
  }

  Widget _buildBody(QueryResult result) {
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
            onKeyEvent: _keyboard.handleKey,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IndexColumn(
                  controller: _vIndex,
                  slots: _slots,
                  deletedRows: widget.deletedRows,
                  selection: _selection,
                ),
                Expanded(child: _buildDataArea(result)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDataArea(QueryResult result) {
    // Opaque backdrop for the whole data area — rows paint translucent
    // state tints on top of it, and the area below the last row inherits
    // the same colour. White in light theme, the page bg in dark (so the
    // dark grid stays visually identical to before this base existed).
    return ColoredBox(
      color: AppColors.gridRowBg,
      child: LayoutBuilder(
        builder: (context, constraints) {
        final minRowWidth = constraints.maxWidth;
        return OverlayPortal(
          controller: _expansion.controller,
          overlayChildBuilder: (_) => _expansion.buildOverlay(
            selection: _selection,
            contextFactory: _expansionContext,
          ),
          child: RepaintBoundary(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                // Any scroll slides cells out from under the cursor — drop the
                // hover expansion rather than leave it anchored to a stale
                // position.
                _expansion.dismiss();
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
              // Outer `SizedBox` width subscribes to `_widths` so a resize
              // tick updates the horizontal scroll extent in place — the body
              // content (gestures + ListView + GridRow) is passed as `child`
              // and reused untouched. Each `GridRow` subscribes independently
              // and re-lays its own cell strip.
              child: SingleChildScrollView(
                controller: _hBody,
                scrollDirection: Axis.horizontal,
                child: ListenableBuilder(
                  listenable: _widths,
                  builder: (_, child) => SizedBox(
                    width: math.max(_widths.total, minRowWidth),
                    child: child,
                  ),
                  child: Builder(
                    builder: (bodyCtx) {
                      _bodyCtx = bodyCtx;
                      return GridBodyGestures(
                        selection: _selection,
                        gridFocus: _gridFocus,
                        editable: widget.editable,
                        cellAt: _cellAt,
                        onHover: _handleCellHover,
                        onExit: _expansion.dismiss,
                        onOpenPicker: (r, c) => _interaction.openCellPicker(
                          bodyCtx,
                          r,
                          c,
                          _originalAt(r, c),
                        ),
                        onOpenMenu: (pos, r, c) => _interaction.openCellMenu(
                          context,
                          bodyCtx,
                          pos,
                          r,
                          c,
                          _originalAt(r, c),
                        ),
                        child: ListView.builder(
                          controller: _vBody,
                          itemCount: _totalRowCount,
                          itemExtent: kRowHeight,
                          padding: const EdgeInsets.only(
                            bottom: kGridBottomGutter,
                          ),
                          // Rows hold no local state (selection lives in a
                          // ValueNotifier). Skipping per-child keepalives
                          // saves a widget allocation per row scrolled in.
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
                              minRowWidth: minRowWidth,
                              columns: result.columns,
                              columnMeta: widget.columnMeta,
                              widths: _widths,
                              selection: _selection,
                              pendingFor: (col) => _pendingFor(r, col),
                              formatCache: _formatCache,
                            );
                          },
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
      ),
    );
  }
}
