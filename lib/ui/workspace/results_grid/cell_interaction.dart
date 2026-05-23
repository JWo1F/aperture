import 'package:flutter/widgets.dart';

import '../../../models/cell_edit.dart';
import '../../cell_picker/cell_picker.dart';
import 'cell_context_menu.dart';
import 'results_grid.dart';

/// Inputs the cell picker / context menu actions need to translate a
/// grid-coordinate row into the state-layer row index, resolve metadata, and
/// dispatch the right [ResultsGrid] callbacks.
class CellInteraction {
  CellInteraction({
    required this.widget,
    required this.columns,
    required this.isInsertRow,
    required this.isDeletedRow,
    required this.pendingFor,
    required this.stateRowFor,
    required this.cellRect,
  });

  final ResultsGrid widget;
  final List<String> columns;
  final bool Function(int row) isInsertRow;
  final bool Function(int row) isDeletedRow;
  final CellEditValue? Function(int row, int column) pendingFor;
  final int Function(int row) stateRowFor;
  final Rect Function(BuildContext bodyCtx, int row, int column) cellRect;

  void openCellPicker(
    BuildContext bodyCtx,
    int row,
    int column,
    Object? original,
  ) {
    if (widget.onEditCell == null) return;
    if (isDeletedRow(row)) return;

    final columnName = columns[column];
    final meta = widget.columnMeta?[columnName];
    final isInsert = isInsertRow(row);
    final pending = pendingFor(row, column);

    showCellPicker(
      bodyCtx,
      anchorRect: cellRect(bodyCtx, row, column),
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
          widget.onEditCell!(stateRowFor(row), column, value),
      // Insert-row cells don't have a "revert to original" — the row itself
      // is the pending operation. Use Delete row to discard it.
      onRevert: (isInsert || pending == null)
          ? null
          : () => widget.onRevertEdit?.call(stateRowFor(row), column),
    );
  }

  void openCellMenu(
    BuildContext anchorContext,
    BuildContext bodyCtx,
    Offset pos,
    int row,
    int column,
    Object? original,
  ) {
    final columnName = columns[column];
    final isInsert = isInsertRow(row);
    final isDeleted = isDeletedRow(row);
    final pending = pendingFor(row, column);
    final fk = widget.foreignKeys?[columnName];
    final owner = widget.findRowOwner?.call(columnName);
    final stateRow = stateRowFor(row);
    final canMutateCell =
        widget.editable && widget.onEditCell != null && !isDeleted;

    showCellContextMenu(
      anchorContext,
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
            ? () => openCellPicker(bodyCtx, row, column, original)
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
}
