import 'dart:typed_data';

import 'package:aperture/models/cell_edit.dart';
import 'package:aperture/ui/cell_picker/editor_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('initialText', () {
    test('a staged literal wins over the stored value', () {
      expect(initialText('stored', const CellLiteral('staged')), 'staged');
    });

    test('a staged NULL and a staged DEFAULT both open empty', () {
      expect(initialText('stored', const CellLiteral(null)), '');
      expect(initialText('stored', const CellDefault()), '');
    });

    test('null opens empty', () {
      expect(initialText(null, null), '');
    });

    test('JSON is pretty-printed with a two-space indent', () {
      expect(initialText({'a': 1}, null), '{\n  "a": 1\n}');
    });

    test('binary opens empty rather than showing an elided preview', () {
      // Editing a 16-byte hex stub back into a blob column would be worse
      // than starting blank.
      expect(initialText(Uint8List.fromList([1, 2, 3]), null), '');
    });

    test('a DateTime opens as ISO-8601, matching formatCellValue', () {
      final dt = DateTime(2026, 5, 23, 14, 32);
      expect(initialText(dt, null), dt.toIso8601String());
    });
  });

  group('initialArrayText', () {
    test('a list opens as a Postgres array literal, not JSON', () {
      expect(initialArrayText([1, 2], null), '{1,2}');
      expect(initialArrayText(['a', null], null), '{"a",NULL}');
    });

    test('a staged literal is shown verbatim', () {
      expect(initialArrayText([1], const CellLiteral('{9}')), '{9}');
    });

    test('null and DEFAULT open empty', () {
      expect(initialArrayText(null, null), '');
      expect(initialArrayText([1], const CellDefault()), '');
    });
  });

  group('initialBool', () {
    test('reads the truthy spellings', () {
      for (final v in ['true', 'TRUE', 't', '1']) {
        expect(initialBool(null, CellLiteral(v)), isTrue, reason: v);
      }
    });

    test('reads the falsy spellings', () {
      for (final v in ['false', 'FALSE', 'f', '0']) {
        expect(initialBool(null, CellLiteral(v)), isFalse, reason: v);
      }
    });

    test('anything else is indeterminate', () {
      expect(initialBool(null, const CellLiteral('maybe')), isNull);
      expect(initialBool(null, const CellLiteral(null)), isNull);
      expect(initialBool('not a bool', null), isNull);
    });

    test('a stored bool passes through', () {
      expect(initialBool(true, null), isTrue);
      expect(initialBool(false, null), isFalse);
    });
  });

  group('initialMoment', () {
    test('a full ISO string parses', () {
      expect(
        initialMoment(null, const CellLiteral('2026-05-23T14:32:10')),
        DateTime(2026, 5, 23, 14, 32, 10),
      );
    });

    test('a time-only literal lands on the epoch date', () {
      expect(
        initialMoment(null, const CellLiteral('09:05:30')),
        DateTime(1970, 1, 1, 9, 5, 30),
      );
    });

    test('a one-digit millisecond is padded, not misread', () {
      expect(
        initialMoment(null, const CellLiteral('01:02:03.4')),
        DateTime(1970, 1, 1, 1, 2, 3, 400),
      );
    });

    test('the decoder output for a time column round-trips', () {
      // decodeDriverValue normalises Postgres `time` to this shape; if it
      // did not parse here the picker would fall through to
      // DateTime.now() and offer to overwrite the stored value.
      expect(
        initialMoment('09:00:00', const CellLiteral('09:00:00')),
        DateTime(1970, 1, 1, 9, 0, 0),
      );
    });

    test('a stored DateTime passes through', () {
      final dt = DateTime(2026, 1, 2, 3, 4);
      expect(initialMoment(dt, null), dt);
    });
  });

  group('initialTz', () {
    test('a numeric offset is extracted', () {
      expect(initialTz(null, const CellLiteral('09:00:00+02:00')), '+02:00');
      expect(initialTz(null, const CellLiteral('09:00:00-0500')), '-0500');
    });

    test('a named zone is extracted', () {
      expect(initialTz(null, const CellLiteral('09:00:00 UTC')), 'UTC');
    });

    test("a date's year is not mistaken for a zone", () {
      expect(initialTz(null, const CellLiteral('2026-05-23')), '');
    });

    test('no pending literal means the server default', () {
      expect(initialTz('09:00:00+02:00', null), '');
    });
  });
}
