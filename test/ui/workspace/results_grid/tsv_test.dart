import 'package:aperture/ui/workspace/results_grid/grid_selection.dart';
import 'package:aperture/ui/workspace/results_grid/tsv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseTsv', () {
    test('empty input yields no rows', () {
      expect(parseTsv(''), isEmpty);
    });

    test('single value', () {
      expect(parseTsv('hello'), [
        ['hello'],
      ]);
    });

    test('tab-separated cells in one row', () {
      expect(parseTsv('a\tb\tc'), [
        ['a', 'b', 'c'],
      ]);
    });

    test('newline-separated rows', () {
      expect(parseTsv('a\tb\nc\td'), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('trailing newline does not add a phantom row', () {
      expect(parseTsv('a\tb\n'), [
        ['a', 'b'],
      ]);
    });

    test('quoted cell preserves tab and newline', () {
      expect(parseTsv('"a\tb"\tc\n"d\ne"\tf'), [
        ['a\tb', 'c'],
        ['d\ne', 'f'],
      ]);
    });

    test('doubled quotes inside a quoted cell collapse to one', () {
      expect(parseTsv('"He said ""hi"""\tthere'), [
        ['He said "hi"', 'there'],
      ]);
    });

    test('CRLF line endings are normalized', () {
      expect(parseTsv('a\tb\r\nc\td'), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('empty cells round-trip', () {
      expect(parseTsv('\ta\t\nb\t\tc'), [
        ['', 'a', ''],
        ['b', '', 'c'],
      ]);
    });

    test('a quoted cell carrying tabs, newlines and quotes is recovered', () {
      final input = '"a\tb"\tc\n"He said ""hi"""\tlast';
      expect(parseTsv(input), [
        ['a\tb', 'c'],
        ['He said "hi"', 'last'],
      ]);
    });
  });

  group('selectionToTsv', () {
    String cell(int r, int c) => 'r${r}c$c';

    test('one rect emits tabs and newlines with no trailing newline', () {
      final sel = GridSelection(ranges: [CellRange.of(0, 0, 1, 1)]);
      expect(selectionToTsv(sel, cell), 'r0c0\tr0c1\nr1c0\tr1c1');
    });

    test('an empty selection yields nothing', () {
      expect(selectionToTsv(const GridSelection(ranges: []), cell), '');
    });

    test('disjoint rects project into the bounding box, blanks between', () {
      // Excel's behaviour: the gap is present but empty, so the block
      // keeps its shape when pasted elsewhere.
      final sel = GridSelection(
        ranges: [CellRange.of(0, 0, 0, 0), CellRange.of(1, 1, 1, 1)],
      );
      expect(selectionToTsv(sel, cell), 'r0c0\t\n\tr1c1');
    });

    test('a value containing a tab, newline or quote is quoted', () {
      final sel = GridSelection(ranges: [CellRange.of(0, 0, 0, 2)]);
      final awkward = ['a\tb', 'c\nd', 'say "hi"'];
      expect(
        selectionToTsv(sel, (r, c) => awkward[c]),
        '"a\tb"\t"c\nd"\t"say ""hi"""',
      );
    });

    test('round-trips through parseTsv', () {
      final sel = GridSelection(ranges: [CellRange.of(0, 0, 0, 2)]);
      final awkward = ['a\tb', 'c\nd', 'say "hi"'];
      expect(parseTsv(selectionToTsv(sel, (r, c) => awkward[c])), [awkward]);
    });
  });
}
