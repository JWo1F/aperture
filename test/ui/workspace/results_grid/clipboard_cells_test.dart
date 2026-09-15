import 'package:aperture/models/cell_edit.dart';
import 'package:aperture/ui/workspace/results_grid/clipboard_cells.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('clipboardCellValue', () {
    test('NULL round-trips as SQL NULL, not as text', () {
      final v = clipboardCellValue(nullToken);
      expect(v, isA<CellLiteral>());
      expect((v as CellLiteral).value, isNull);
    });

    test('DEFAULT round-trips as the DEFAULT directive', () {
      expect(clipboardCellValue(defaultToken), isA<CellDefault>());
    });

    test('anything else is a literal, verbatim', () {
      for (final text in ['', 'null', 'Null', 'NULLABLE', ' NULL', '0', 'x']) {
        final v = clipboardCellValue(text);
        expect(v, isA<CellLiteral>(), reason: text);
        expect((v as CellLiteral).value, text, reason: text);
      }
    });

    test('an empty cell stays an empty string, never NULL', () {
      // A blank in a pasted TSV block means "the source cell was empty
      // text"; only the NULL token means SQL NULL.
      expect((clipboardCellValue('') as CellLiteral).value, '');
    });
  });
}
