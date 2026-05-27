import 'package:dbv/ui/workspace/results_grid/tsv.dart';
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

    test('selectionToTsv round-trips through parseTsv', () {
      final input = '"a\tb"\tc\n"He said ""hi"""\tlast';
      expect(parseTsv(input), [
        ['a\tb', 'c'],
        ['He said "hi"', 'last'],
      ]);
    });
  });
}
