/// What a cell is being changed to.
///
/// Either a literal text value (null = SQL `NULL`) or the special
/// `DEFAULT` directive. Lives in `models/` rather than `state/` so the
/// service layer (which builds the UPDATE statements) doesn't need to
/// reach upward into `state/`.
sealed class CellEditValue {
  const CellEditValue();
}

class CellLiteral extends CellEditValue {
  const CellLiteral(this.value);

  final String? value;
}

class CellDefault extends CellEditValue {
  const CellDefault();
}

/// One pending cell edit coordinate. Lives alongside [CellEditValue] so the
/// grid / cell picker / pending-edits modal share one import.
class CellEdit {
  CellEdit(this.row, this.column);

  final int row;
  final int column;

  @override
  bool operator ==(Object other) =>
      other is CellEdit && other.row == row && other.column == column;

  @override
  int get hashCode => Object.hash(row, column);
}
