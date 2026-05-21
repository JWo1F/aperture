import '../../state/workspace_tab.dart' show CellEditValue;

/// What the picker needs to know about the column it's editing. Bundled to
/// keep `showCellPicker`'s signature and the downstream widget constructors
/// from growing a long parallel list of parameters.
class CellEditTarget {
  const CellEditTarget({
    required this.columnName,
    required this.originalValue,
    required this.pendingEdit,
    this.canBeNull = true,
    this.hasDefault = false,
    this.columnDataType,
    this.isPrimaryKey = false,
    this.isForeignKey = false,
  });

  final String columnName;
  final Object? originalValue;
  final CellEditValue? pendingEdit;
  final bool canBeNull;
  final bool hasDefault;
  final String? columnDataType;
  final bool isPrimaryKey;
  final bool isForeignKey;
}
