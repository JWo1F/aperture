import 'dart:typed_data';

import 'package:dbv/models/value_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatCellValue', () {
    test('null → null', () {
      expect(formatCellValue(null), isNull);
    });

    test('primitives use toString', () {
      expect(formatCellValue(42), '42');
      expect(formatCellValue(1.5), '1.5');
      expect(formatCellValue(true), 'true');
    });

    test('Map and List encode as JSON', () {
      expect(formatCellValue({'a': 1, 'b': 'x'}), '{"a":1,"b":"x"}');
      expect(formatCellValue([1, 2, 3]), '[1,2,3]');
    });

    test('Uint8List renders a hex preview', () {
      final bytes = Uint8List.fromList([1, 2, 3, 0xFF]);
      expect(formatCellValue(bytes), r'\x010203ff');
    });

    test('long Uint8List truncates with ellipsis', () {
      final bytes = Uint8List.fromList(List<int>.generate(40, (i) => i));
      final formatted = formatCellValue(bytes)!;
      expect(formatted.startsWith(r'\x'), isTrue);
      expect(formatted.endsWith('…'), isTrue);
    });
  });

  group('equalityFragment', () {
    test('null becomes IS NULL / IS NOT NULL', () {
      expect(equalityFragment('id', null), '"id" IS NULL');
      expect(equalityFragment('id', null, not: true), '"id" IS NOT NULL');
    });

    test('numeric values render unquoted', () {
      expect(equalityFragment('count', 42), '"count" = 42');
      expect(equalityFragment('count', 42, not: true), '"count" != 42');
    });

    test('strings get single quotes doubled', () {
      expect(
        equalityFragment('name', "O'Brien"),
        '"name" = \'O\'\'Brien\'',
      );
    });

    test('embedded double-quotes in column names are escaped', () {
      expect(
        equalityFragment('weird"col', 1),
        '"weird""col" = 1',
      );
    });

    test('bool / BigInt go unquoted', () {
      expect(equalityFragment('active', true), '"active" = true');
      expect(equalityFragment('big', BigInt.from(9)), '"big" = 9');
    });
  });
}
