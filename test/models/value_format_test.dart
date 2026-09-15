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

    test('the exact form keeps every byte of a long Uint8List', () {
      final bytes = Uint8List.fromList(List<int>.generate(40, (i) => i));
      final exact = exactCellValue(bytes)!;
      // Export and clipboard read through this: an elided preview would
      // hand out 16 bytes of a 40-byte blob and call it the value.
      expect(exact.endsWith('…'), isFalse);
      expect(exact, r'\x000102030405060708090a0b0c0d0e0f'
          '101112131415161718191a1b1c1d1e1f'
          '2021222324252627');
    });

    test('the exact form matches the display form for everything else', () {
      for (final v in <Object?>[
        null,
        'plain',
        42,
        1.5,
        true,
        BigInt.two,
        DateTime(2026, 5, 23),
        {'a': 1},
        [1, 2],
      ]) {
        expect(exactCellValue(v), formatCellValue(v), reason: '$v');
      }
    });

    test('DateTime (local) renders as naive ISO-8601 (no Z)', () {
      final dt = DateTime(2026, 5, 23, 14, 32, 10, 123);
      expect(formatCellValue(dt), dt.toIso8601String());
      expect(formatCellValue(dt), '2026-05-23T14:32:10.123');
    });

    test('DateTime (UTC) renders with trailing Z', () {
      final dt = DateTime.utc(2026, 5, 23, 14, 32, 10);
      expect(formatCellValue(dt), '2026-05-23T14:32:10.000Z');
    });

    test('Map with nested DateTime encodes value as ISO-8601 string', () {
      final dt = DateTime.utc(2026, 5, 23, 14, 32, 10);
      final out = formatCellValue({'at': dt, 'n': 7});
      expect(out, '{"at":"2026-05-23T14:32:10.000Z","n":7}');
    });

    test('List with nested DateTime encodes as ISO-8601 string', () {
      final dt = DateTime.utc(2026, 1, 1);
      expect(
        formatCellValue([dt, 'x']),
        '["2026-01-01T00:00:00.000Z","x"]',
      );
    });

    test('Deeply nested DateTime is encoded throughout', () {
      final dt = DateTime.utc(2026, 5, 23, 14, 32, 10);
      final out = formatCellValue({
        'events': [
          {'at': dt, 'kind': 'a'},
          {'at': dt, 'kind': 'b'},
        ],
      });
      expect(
        out,
        '{"events":['
        '{"at":"2026-05-23T14:32:10.000Z","kind":"a"},'
        '{"at":"2026-05-23T14:32:10.000Z","kind":"b"}'
        ']}',
      );
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
