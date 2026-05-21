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

/// A row scheduled for INSERT. Values are keyed by column name; columns
/// absent from the map are omitted from the column list, so the database
/// uses the table default. Produced by Duplicate row (primary-key columns
/// pre-populated as [CellDefault]).
///
/// [afterRow] anchors the visual position: the grid renders this insert
/// immediately below `result.rows[afterRow]`. `null` means "append at the
/// end" — used for inserts whose anchor went stale (e.g. duplicated from
/// another insert, or the source row scrolled off the page).
class PendingInsert {
  PendingInsert({this.afterRow, Map<String, CellEditValue>? values})
    : values = values ?? <String, CellEditValue>{};

  final int? afterRow;
  final Map<String, CellEditValue> values;
}

/// Bundle of pending mutations against a single relation. Built once per
/// preview or apply pass — the same shape feeds both `buildEditStatements`
/// (for the modal) and `TableRepository.applyEdits` (for the transaction).
class EditBatch {
  EditBatch({
    Map<String, Map<String, CellEditValue>>? updatesByCtid,
    List<String>? deleteCtids,
    List<PendingInsert>? inserts,
  }) : updatesByCtid =
           updatesByCtid ?? <String, Map<String, CellEditValue>>{},
       deleteCtids = deleteCtids ?? const <String>[],
       inserts = inserts ?? const <PendingInsert>[];

  final Map<String, Map<String, CellEditValue>> updatesByCtid;
  final List<String> deleteCtids;
  final List<PendingInsert> inserts;

  bool get isEmpty =>
      updatesByCtid.isEmpty && deleteCtids.isEmpty && inserts.isEmpty;

  int get statementCount =>
      updatesByCtid.length + deleteCtids.length + inserts.length;
}
