import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

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
  final void Function(DbTable table, String column, Object? value)?
      onFindRow;

  @override
  State<ResultsGrid> createState() => _ResultsGridState();
}

class _ResultsGridState extends State<ResultsGrid> {
  static const double _rowHeight = 26;
  static const double _indexWidth = 56;
  static const double _handleWidth = 7;

  // The body owns horizontal scroll outright; the header reads its offset
  // through an AnimatedBuilder so it tracks every pixel of the gesture in
  // the same frame. LinkedScrollControllerGroup syncs through a microtask
  // and adds a visible one-frame lag that made trackpad scrolling feel
  // rubbery on macOS.
  final ScrollController _hBody = ScrollController();
  final ScrollController _vBody = ScrollController();

  /// Focus node for the grid body — owns keyboard shortcuts (⌘C / Ctrl-C
  /// to copy the selected cell, Esc to clear the selection). Lazily takes
  /// focus on the first cell click so the toolbar text fields keep their
  /// default editing keybindings while no cell is active.
  final FocusNode _gridFocus = FocusNode(debugLabel: 'results-grid');

  /// The current selection — a set of cell ranges plus an anchor (shift-
  /// extension reference) and a focus (the active cell for keyboard nav,
  /// editing, and context-menu actions). Empty until the user clicks; reset
  /// when the result set changes. Stored in a notifier so only visible rows
  /// rebuild on selection updates, not the whole grid.
  final ValueNotifier<_GridSelection> _selection =
      ValueNotifier<_GridSelection>(_GridSelection.empty);

  int? get _selRow => _selection.value.focus?.$1;
  int? get _selCol => _selection.value.focus?.$2;

  /// In-progress drag anchor: the cell where the pointer went down. While
  /// non-null every `onPointerMove` extends the last range from this point.
  ({int row, int col})? _drag;

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
  static const int _autoSampleRows = 50;

  @override
  void initState() {
    super.initState();
    _syncWidths();
  }

  @override
  void didUpdateWidget(ResultsGrid old) {
    super.didUpdateWidget(old);
    if (!listEquals(widget.result.columns, _widthKeys)) {
      _syncWidths();
    } else if (!identical(old.result, widget.result)) {
      _syncWidths();
    }
    // A new result set invalidates the row/column indices we held; clearing
    // the selection avoids highlighting an arbitrary cell after pagination.
    if (!identical(old.result, widget.result)) {
      _selection.value = _GridSelection.empty;
      _drag = null;
    }
  }

  /// Default width = widest visible cell (and the header) in this column,
  /// clamped between [_autoMin] and [_autoMax]. Cells already ellipsize, so
  /// we measure at most the first 200 chars of each value to keep this cheap.
  ///
  /// We only sample the first [_autoSampleRows] rows: pages can hit several
  /// thousand rows and measuring every one ran formatCellValue + layout in a
  /// tight loop on the UI thread, blocking the first frame for ~500 ms+. A
  /// fixed sample is enough to pick a reasonable default — the user can drag
  /// the handle if it guesses short.
  double _autoWidth(String column, int columnIndex) {
    final headerStyle = AppTheme.mono(
      size: 11.5,
      weight: FontWeight.w600,
    );

    _measurer
      ..text = TextSpan(text: column, style: headerStyle)
      ..layout();
    var widest = _measurer.width + _headerExtra;

    final rows = widget.result.rows;
    final n = rows.length < _autoSampleRows ? rows.length : _autoSampleRows;
    for (var r = 0; r < n; r++) {
      final raw = rows[r][columnIndex];
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
    _hBody.dispose();
    _vBody.dispose();
    _gridFocus.dispose();
    _measurer.dispose();
    _selection.dispose();
    super.dispose();
  }

  // --- selection -------------------------------------------------------

  void _selectCell(int row, int column) {
    _selection.value = _GridSelection.single(row, column);
    if (!_gridFocus.hasFocus) _gridFocus.requestFocus();
  }

  /// Begin (or extend) a selection at the pointer-down cell. Drag tracking
  /// is set up so subsequent `onPointerMove` events grow the last range.
  void _beginPointerSelection(int row, int column) {
    final cmd = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final current = _selection.value;

    if (shift && current.anchor != null) {
      final a = current.anchor!;
      _selection.value =
          current.replaceLast(a.$1, a.$2, row, column, focus: (row, column));
      _drag = (row: a.$1, col: a.$2);
    } else if (cmd && !current.isEmpty) {
      _selection.value = current.addRange(row, column);
      _drag = (row: row, col: column);
    } else {
      _selection.value = _GridSelection.single(row, column);
      _drag = (row: row, col: column);
    }
    if (!_gridFocus.hasFocus) _gridFocus.requestFocus();
  }

  /// Extend the last range from the drag anchor to (row, column) and move
  /// the focus there. Called from `onPointerMove` while a drag is active.
  void _extendDragTo(int row, int column) {
    final d = _drag;
    if (d == null) return;
    _selection.value = _selection.value
        .replaceLast(d.row, d.col, row, column, focus: (row, column));
  }

  void _clearSelection() {
    if (_selection.value.isEmpty) return;
    _selection.value = _GridSelection.empty;
  }

  /// Returns the textual form of the focus cell — pending edit (if any)
  /// wins over the original, mirroring what's painted in the grid.
  String _selectedCellText() {
    final focus = _selection.value.focus!;
    return _cellTextAt(focus.$1, focus.$2);
  }

  String _cellTextAt(int row, int column) {
    final pending = widget.edits?[CellEdit(row, column)];
    if (pending is CellLiteral) return pending.value ?? 'NULL';
    if (pending is CellDefault) return 'DEFAULT';
    final formatted = formatCellValue(widget.result.rows[row][column]);
    return formatted ?? 'NULL';
  }

  /// Excel-style TSV of the current selection: tabs between columns,
  /// newlines between rows. A single rect is emitted as-is. Multiple
  /// disjoint rects are projected into the bounding box, leaving blank
  /// cells where nothing is selected. Tabs/newlines/quotes inside values
  /// are wrapped in `"…"` with internal `"` doubled — the same convention
  /// Excel and Sheets use when copying TSV to the system clipboard.
  String _selectionAsTabular() {
    final sel = _selection.value;
    if (sel.isEmpty) return '';

    final ranges = sel.ranges;
    var minR = ranges.first.r0, maxR = ranges.first.r1;
    var minC = ranges.first.c0, maxC = ranges.first.c1;
    for (final rg in ranges) {
      if (rg.r0 < minR) minR = rg.r0;
      if (rg.r1 > maxR) maxR = rg.r1;
      if (rg.c0 < minC) minC = rg.c0;
      if (rg.c1 > maxC) maxC = rg.c1;
    }

    final out = StringBuffer();
    for (var r = minR; r <= maxR; r++) {
      for (var c = minC; c <= maxC; c++) {
        if (c > minC) out.write('\t');
        if (sel.contains(r, c)) out.write(_quoteForTsv(_cellTextAt(r, c)));
      }
      if (r < maxR) out.write('\n');
    }
    return out.toString();
  }

  static String _quoteForTsv(String s) {
    if (s.contains('\t') || s.contains('\n') || s.contains('"')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  BuildContext? _bodyCtx;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_selection.value.isEmpty) return KeyEventResult.ignored;
      _clearSelection();
      return KeyEventResult.handled;
    }
    final isCopyChord = key == LogicalKeyboardKey.keyC &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed);
    if (isCopyChord && !_selection.value.isEmpty) {
      final sel = _selection.value;
      final text = (sel.ranges.length == 1 &&
              sel.ranges.first.r0 == sel.ranges.first.r1 &&
              sel.ranges.first.c0 == sel.ranges.first.c1)
          ? _selectedCellText()
          : _selectionAsTabular();
      Clipboard.setData(ClipboardData(text: text));
      return KeyEventResult.handled;
    }

    if (_moveSelection(key)) return KeyEventResult.handled;

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
        widget.result.rows[_selRow!][_selCol!],
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Handles arrow-key navigation (with Home/End/PageUp/PageDown). Returns
  /// true when the event was consumed. With no selection, any arrow lands
  /// on (0, 0) so the user can take over after a fresh focus. Holding Shift
  /// extends the last range from the anchor instead of collapsing to a
  /// single cell.
  bool _moveSelection(LogicalKeyboardKey key) {
    final rows = widget.result.rows.length;
    final cols = widget.result.columns.length;
    if (rows == 0 || cols == 0) return false;

    int? r = _selRow;
    int? c = _selCol;
    if (key == LogicalKeyboardKey.arrowUp) {
      r = r == null ? 0 : (r - 1).clamp(0, rows - 1);
      c = c ?? 0;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      r = r == null ? 0 : (r + 1).clamp(0, rows - 1);
      c = c ?? 0;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      c = c == null ? 0 : (c - 1).clamp(0, cols - 1);
      r = r ?? 0;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      c = c == null ? 0 : (c + 1).clamp(0, cols - 1);
      r = r ?? 0;
    } else if (key == LogicalKeyboardKey.home) {
      r = r ?? 0;
      c = 0;
    } else if (key == LogicalKeyboardKey.end) {
      r = r ?? 0;
      c = cols - 1;
    } else if (key == LogicalKeyboardKey.pageUp) {
      r = r == null ? 0 : (r - _pageJump).clamp(0, rows - 1);
      c = c ?? 0;
    } else if (key == LogicalKeyboardKey.pageDown) {
      r = r == null ? 0 : (r + _pageJump).clamp(0, rows - 1);
      c = c ?? 0;
    } else {
      return false;
    }
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final anchor = _selection.value.anchor;
    if (shift && anchor != null) {
      _selection.value = _selection.value
          .replaceLast(anchor.$1, anchor.$2, r, c, focus: (r, c));
    } else {
      _selectCell(r, c);
    }
    _scrollToCell(r, c);
    return true;
  }

  static const int _pageJump = 20;

  /// Nudge the body scrollers so the cell sits inside the viewport. We
  /// scroll only when the cell is off-screen — no jitter on every arrow.
  void _scrollToCell(int row, int col) {
    if (_vBody.hasClients) {
      final top = row * _rowHeight;
      final bottom = top + _rowHeight;
      final viewport = _vBody.position.viewportDimension;
      final offset = _vBody.offset;
      if (top < offset) {
        _vBody.jumpTo(top);
      } else if (bottom > offset + viewport) {
        _vBody.jumpTo(bottom - viewport);
      }
    }
    if (_hBody.hasClients) {
      var left = _indexWidth;
      for (var i = 0; i < col; i++) {
        left += _widths[i];
      }
      final right = left + _widths[col];
      final viewport = _hBody.position.viewportDimension;
      final offset = _hBody.offset;
      if (left < offset + _indexWidth) {
        _hBody.jumpTo(math.max(0, left - _indexWidth));
      } else if (right > offset + viewport) {
        _hBody.jumpTo(right - viewport);
      }
    }
  }

  // --- cell hit-testing & geometry --------------------------------------

  /// Maps a local-position pointer event on the body Listener to its cell.
  /// Returns `null` for clicks on the row-number gutter or outside the grid.
  (int, int)? _cellAt(Offset localPos) {
    if (localPos.dx < _indexWidth) return null;
    var x = _indexWidth;
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
    final row = (contentY / _rowHeight).floor();
    if (row < 0 || row >= widget.result.rows.length) return null;

    return (row, col);
  }

  /// Computes the cell's current global Rect from the body's RenderBox plus
  /// column/row geometry — used as the picker overlay's anchor since cells
  /// no longer carry their own per-cell BuildContext.
  Rect _cellRect(BuildContext bodyCtx, int row, int col) {
    final box = bodyCtx.findRenderObject();
    if (box is! RenderBox) return Rect.zero;
    final origin = box.localToGlobal(Offset.zero);

    var contentX = _indexWidth;
    for (var i = 0; i < col; i++) {
      contentX += _widths[i];
    }
    final viewportY =
        row * _rowHeight - (_vBody.hasClients ? _vBody.offset : 0);

    return Rect.fromLTWH(
      origin.dx + contentX,
      origin.dy + viewportY,
      _widths[col],
      _rowHeight,
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

    final columnName = widget.result.columns[column];
    final key = CellEdit(row, column);
    final pending = widget.edits?[key];
    final meta = widget.columnMeta?[columnName];

    showCellPicker(
      bodyCtx,
      anchorRect: _cellRect(bodyCtx, row, column),
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

  Color _colorFor(Object? value, {String? dataType}) {
    if (value == null) return AppColors.tNull;
    if (value is bool) return value ? AppColors.tBool : AppColors.textMuted;
    if (value is num || value is BigInt) return AppColors.tNum;
    if (value is DateTime) return AppColors.tDate;
    if (value is Map || value is List) return AppColors.tJson;
    final dt = dataType?.toLowerCase() ?? '';
    if (dt.contains('uuid')) return AppColors.tUuid;
    if (dt.contains('date') || dt.contains('time') || dt.contains('stamp')) {
      return AppColors.tDate;
    }
    if (dt.contains('json')) return AppColors.tJson;
    return AppColors.tStr;
  }

  bool _wantsTooltip(Object? original, String text) {
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
    Object? original,
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
    final headerRow = SizedBox(
      width: totalWidth,
      child: Row(
        children: [
          Container(
            width: _indexWidth,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: AppColors.border),
              ),
            ),
            child: Text(
              '#',
              style: AppTheme.mono(size: 10, color: AppColors.text4),
            ),
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
              isPrimaryKey:
                  widget.columnMeta?[columns[i]]?.isPrimaryKey ?? false,
              typeLabel: widget.columnMeta?[columns[i]]?.dataType,
              onSort: widget.onSortColumn == null
                  ? null
                  : () => widget.onSortColumn!(columns[i]),
              onResize: (delta) {
                final next = (_widths[i] + delta).clamp(64.0, 900.0);
                setState(() => _widths[i] = next);
                widget.widths?[columns[i]] = next;
                widget.onWidthChanged?.call(columns[i], next);
              },
            ),
        ],
      ),
    );

    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      // ClipRect alone would force the header row to fit the viewport
      // (Transform passes parent constraints through). OverflowBox grants
      // it the same unbounded horizontal space the body's scroll view has,
      // so the Row lays out at `totalWidth` and we translate it sideways
      // to mirror the body's scroll offset.
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
          child: headerRow,
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
                // The outer RepaintBoundary isolates the body's pixels
                // from the scrollbar thumb overlay so vertical thumb
                // drags don't force a repaint of every visible row.
                //
                // A single Listener + GestureDetector at the body level
                // owns click / double-click / right-click for every cell.
                // Per-cell pointer handlers used to be allocated for every
                // new row that scrolled into view — that churn was the
                // biggest cost during fast scrolling. We hit-test (row,
                // column) from the pointer's local position instead.
                return RepaintBoundary(
                  child: MouseRegion(
                    cursor: widget.editable
                        ? SystemMouseCursors.text
                        : SystemMouseCursors.basic,
                    child: SingleChildScrollView(
                      controller: _hBody,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: bodyWidth,
                        child: Builder(
                          builder: (bodyCtx) {
                            _bodyCtx = bodyCtx;
                            return Listener(
                            behavior: HitTestBehavior.translucent,
                            onPointerDown: (e) {
                              final cell = _cellAt(e.localPosition);
                              if (cell == null) return;
                              _beginPointerSelection(cell.$1, cell.$2);
                            },
                            onPointerMove: (e) {
                              if (_drag == null) return;
                              final cell = _cellAt(e.localPosition);
                              if (cell == null) return;
                              _extendDragTo(cell.$1, cell.$2);
                            },
                            onPointerUp: (_) => _drag = null,
                            onPointerCancel: (_) => _drag = null,
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
                                        result.rows[r][c],
                                      );
                                    }
                                  : null,
                              onSecondaryTapDown: (d) {
                                final cell = _cellAt(d.localPosition);
                                if (cell == null) return;
                                final (r, c) = cell;
                                // Right-clicking inside an existing
                                // multi-selection keeps it intact so a
                                // "Copy" from the menu reflects the whole
                                // range; clicking outside collapses to
                                // the targeted cell.
                                if (!_selection.value.contains(r, c)) {
                                  _selectCell(r, c);
                                }
                                _openCellMenu(
                                  bodyCtx,
                                  d.globalPosition,
                                  r,
                                  c,
                                  result.rows[r][c],
                                );
                              },
                              child: ListView.builder(
                                controller: _vBody,
                                itemCount: result.rows.length,
                                itemExtent: _rowHeight,
                                // Rows hold no local state (selection lives
                                // in a ValueNotifier on the grid). Skipping
                                // the per-child AutomaticKeepAlive wrapper
                                // means one less widget allocated per row
                                // that scrolls into view.
                                addAutomaticKeepAlives: false,
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
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(int row, List<Object?> values, double rowWidth) {
    // Cells are built once per row. Their content doesn't depend on the
    // selection, so we don't put them inside the ValueListenableBuilder.
    // The selection ring overlay is drawn once at the row level (a single
    // Positioned widget over the active column) instead of giving every
    // visible cell its own ValueListenableBuilder + Stack — that previously
    // meant ~200 listener subscriptions churning on each scroll tick.
    final cells = <Widget>[
      for (var c = 0; c < values.length; c++) _buildCell(row, c, values[c]),
    ];

    return StatefulBuilder(
      builder: (_, setRowState) {
        var hovering = false;
        return MouseRegion(
          onEnter: (_) => setRowState(() => hovering = true),
          onExit: (_) => setRowState(() => hovering = false),
          child: ValueListenableBuilder<_GridSelection>(
            valueListenable: _selection,
            builder: (_, sel, _) {
              final segments = sel.rowSegments(row);
              final hasSelection = segments.isNotEmpty;
              final bg = hasSelection
                  ? const Color(0x1A5B7CFA)
                  : (hovering ? const Color(0x06FFFFFF) : Colors.transparent);

              final body = Container(
                width: rowWidth,
                decoration: BoxDecoration(
                  color: bg,
                  border: Border(
                    bottom: BorderSide(color: AppColors.hairline),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: _indexWidth,
                      height: _rowHeight,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        border: Border(
                          right: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: Text(
                        '${row + 1}',
                        style: AppTheme.mono(
                          size: 10,
                          color: hasSelection
                              ? AppColors.accent
                              : AppColors.text4,
                          weight: hasSelection
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    ...cells,
                  ],
                ),
              );

              if (!hasSelection) return body;

              // Layer a tint over each contiguous selected column segment
              // and, if this row owns the focus cell, draw the indigo ring
              // on top.
              final overlays = <Widget>[];
              for (final segment in segments) {
                final (sc0, sc1) = segment;
                var x = _indexWidth;
                for (var c = 0; c < sc0; c++) {
                  x += _widths[c];
                }
                var w = 0.0;
                for (var c = sc0; c <= sc1 && c < _widths.length; c++) {
                  w += _widths[c];
                }
                overlays.add(
                  Positioned(
                    left: x,
                    top: 0,
                    width: w,
                    height: _rowHeight,
                    child: const IgnorePointer(
                      child: ColoredBox(color: Color(0x1A5B7CFA)),
                    ),
                  ),
                );
              }

              final focus = sel.focus;
              if (focus != null &&
                  focus.$1 == row &&
                  focus.$2 < _widths.length) {
                var x = _indexWidth;
                for (var c = 0; c < focus.$2; c++) {
                  x += _widths[c];
                }
                overlays.add(
                  Positioned(
                    left: x,
                    top: 0,
                    width: _widths[focus.$2],
                    height: _rowHeight,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.fromBorderSide(
                            BorderSide(color: AppColors.accent, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }

              return Stack(children: [body, ...overlays]);
            },
          ),
        );
      },
    );
  }

  Widget _buildCell(int row, int column, Object? original) {
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
            color: isEdited
                ? AppColors.textPrimary
                : _colorFor(
                    original,
                    dataType: widget
                        .columnMeta?[widget.result.columns[column]]
                        ?.dataType,
                  ),
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

    // Pointer handling lives at the body level — a single Listener +
    // GestureDetector hit-tests (row, column) from the click's local
    // position. Cells reduce to a sized Container, which keeps the per-row
    // widget allocation small enough for fast scrolling.
    return Container(
      width: _widths[column],
      height: _rowHeight,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: isEdited
          ? BoxDecoration(
              color: AppColors.accentSoft,
              border: Border(
                left: BorderSide(color: AppColors.accent, width: 2),
              ),
            )
          : null,
      child: rendered,
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
    this.isPrimaryKey = false,
    this.typeLabel,
  });

  final String label;
  final double width;
  final double handleWidth;
  final ValueChanged<double> onResize;
  final OrderTerm? sort;
  final int sortPriority;
  final VoidCallback? onSort;
  final bool isForeignKey;
  final bool isPrimaryKey;
  final String? typeLabel;

  @override
  State<_HeaderCell> createState() => _HeaderCellState();
}

class _HeaderCellState extends State<_HeaderCell> {
  @override
  Widget build(BuildContext context) {
    final sort = widget.sort;
    final sortable = widget.onSort != null;
    final Color nameColor = widget.isPrimaryKey
        ? AppColors.accent
        : widget.isForeignKey
            ? AppColors.tFk
            : AppColors.textPrimary;

    return SizedBox(
      width: widget.width,
      height: 28,
      child: Stack(
        children: [
          Hoverable(
            cursor: sortable
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onTap: widget.onSort,
            builder: (context, hovering) => Container(
              decoration: BoxDecoration(
                color: hovering && sortable
                    ? AppColors.surfaceHover
                    : AppColors.bgDeep,
                border: Border(
                  right: BorderSide(color: AppColors.hairline, width: 1),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  if (widget.isPrimaryKey) ...[
                    Icon(Icons.vpn_key, size: 10, color: AppColors.accent),
                    const SizedBox(width: 5),
                  ] else if (widget.isForeignKey) ...[
                    Icon(Icons.north_east, size: 10, color: AppColors.tFk),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.mono(
                        size: 11,
                        color: nameColor,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.typeLabel != null) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.typeLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.mono(
                          size: 10,
                          color: AppColors.text4,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                  if (sort != null) ...[
                    const Spacer(),
                    Icon(
                      sort.descending
                          ? Icons.arrow_downward
                          : Icons.arrow_upward,
                      size: 11,
                      color: AppColors.accent,
                    ),
                    if (widget.sortPriority > 0) ...[
                      const SizedBox(width: 2),
                      Text(
                        '${widget.sortPriority}',
                        style: AppTheme.mono(
                          size: 9,
                          color: AppColors.accent,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ],
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
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One rectangular block of selected cells, stored in canonical form
/// (r0 ≤ r1, c0 ≤ c1) so callers don't have to normalize at every read.
class _CellRange {
  factory _CellRange.of(int r0, int c0, int r1, int c1) => _CellRange._(
        r0 < r1 ? r0 : r1,
        c0 < c1 ? c0 : c1,
        r0 > r1 ? r0 : r1,
        c0 > c1 ? c0 : c1,
      );

  const _CellRange._(this.r0, this.c0, this.r1, this.c1);

  final int r0, c0, r1, c1;

  bool contains(int r, int c) =>
      r >= r0 && r <= r1 && c >= c0 && c <= c1;

  bool containsRow(int r) => r >= r0 && r <= r1;
}

/// Excel-style selection: a stack of ranges plus an anchor (the cell that
/// shift-extension grows from) and a focus (the active cell — the one
/// keyboard navigation, the cell picker, and the context menu act on).
class _GridSelection {
  const _GridSelection({this.ranges = const [], this.anchor, this.focus});

  static const empty = _GridSelection();

  final List<_CellRange> ranges;
  final (int, int)? anchor;
  final (int, int)? focus;

  bool get isEmpty => ranges.isEmpty;

  factory _GridSelection.single(int row, int col) => _GridSelection(
        ranges: [_CellRange._(row, col, row, col)],
        anchor: (row, col),
        focus: (row, col),
      );

  bool contains(int row, int col) {
    for (final rg in ranges) {
      if (rg.contains(row, col)) return true;
    }
    return false;
  }

  /// Column intervals (c0, c1) that intersect [row]. Overlapping or
  /// adjacent intervals are merged so the row paints one continuous tint
  /// strip per visual block.
  List<(int, int)> rowSegments(int row) {
    final hits = <(int, int)>[];
    for (final rg in ranges) {
      if (rg.containsRow(row)) hits.add((rg.c0, rg.c1));
    }
    if (hits.length < 2) return hits;
    hits.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    var (lo, hi) = hits.first;
    for (var i = 1; i < hits.length; i++) {
      final (nlo, nhi) = hits[i];
      if (nlo <= hi + 1) {
        if (nhi > hi) hi = nhi;
      } else {
        merged.add((lo, hi));
        lo = nlo;
        hi = nhi;
      }
    }
    merged.add((lo, hi));
    return merged;
  }

  _GridSelection addRange(int row, int col) => _GridSelection(
        ranges: [...ranges, _CellRange._(row, col, row, col)],
        anchor: (row, col),
        focus: (row, col),
      );

  /// Replace the last range with bbox((r0,c0), (r1,c1)). Anchor stays at
  /// (r0,c0); focus moves to the supplied [focus] (defaults to (r1,c1)).
  /// If there are no ranges yet, the bbox is added as the only range.
  _GridSelection replaceLast(
    int r0,
    int c0,
    int r1,
    int c1, {
    (int, int)? focus,
  }) {
    final next = _CellRange.of(r0, c0, r1, c1);
    final list = ranges.isEmpty
        ? [next]
        : [...ranges.sublist(0, ranges.length - 1), next];
    return _GridSelection(
      ranges: list,
      anchor: (r0, c0),
      focus: focus ?? (r1, c1),
    );
  }
}
