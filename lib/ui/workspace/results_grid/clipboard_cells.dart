import '../../../models/cell_edit.dart';

/// The two non-value cells the grid can hold, as they appear on the
/// clipboard.
///
/// Rendering and parsing live together so they cannot drift: if copy emits
/// `NULL` for an empty cell, paste has to read `NULL` back as SQL NULL
/// rather than as four characters of text.
const String nullToken = 'NULL';
const String defaultToken = 'DEFAULT';

/// Reads one clipboard cell into the value a paste should stage.
///
/// [nullToken] and [defaultToken] match exactly and case-sensitively —
/// they're the spelling copy produces, and a looser match would turn a
/// column that genuinely contains the word "null" into SQL NULL on paste.
/// The cost is that the literal text `NULL` can't be pasted into a text
/// column; use the cell editor for that.
CellEditValue clipboardCellValue(String text) => switch (text) {
  nullToken => const CellLiteral(null),
  defaultToken => const CellDefault(),
  _ => CellLiteral(text),
};
