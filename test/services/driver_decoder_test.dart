import 'dart:convert';
import 'dart:typed_data';

import 'package:aperture/services/driver_decoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';

UndecodedBytes _binary(int oid, List<int> bytes) => UndecodedBytes(
  typeOid: oid,
  isBinary: true,
  bytes: Uint8List.fromList(bytes),
  encoding: utf8,
);

UndecodedBytes _text(String value) => UndecodedBytes(
  typeOid: 0,
  isBinary: false,
  bytes: Uint8List.fromList(utf8.encode(value)),
  encoding: utf8,
);

Uint8List _timetzBytes(int micros, int zoneSecondsWest) {
  final b = ByteData(12)
    ..setInt64(0, micros)
    ..setInt32(8, zoneSecondsWest);
  return b.buffer.asUint8List();
}

void main() {
  group('decodeDriverValue — time', () {
    test('a whole second renders without a fractional part', () {
      final nine = Time(9, 0, 0);
      expect(decodeDriverValue(nine), '09:00:00');
    });

    test('milliseconds survive, trailing zeros do not', () {
      expect(decodeDriverValue(Time(1, 2, 3, 400)), '01:02:03.4');
      expect(decodeDriverValue(Time(1, 2, 3, 0, 500)), '01:02:03.0005');
    });

    test('midnight and the last microsecond of the day both render', () {
      expect(decodeDriverValue(Time(0, 0, 0)), '00:00:00');
      expect(decodeDriverValue(Time(23, 59, 59, 999, 999)), '23:59:59.999999');
    });

    test('the text is what the cell picker parses back', () {
      // The picker's time-only branch matches HH:MM:SS(.mmm); anything it
      // cannot parse falls through to DateTime.now() and silently offers
      // to overwrite the stored value with the current wall clock.
      final text = decodeDriverValue(Time(9, 5, 30)) as String;
      expect(
        RegExp(r'^(\d{1,2}):(\d{1,2})(?::(\d{1,2})(?:\.(\d{1,3}))?)?')
            .hasMatch(text),
        isTrue,
      );
    });
  });

  group('decodeDriverValue — timetz', () {
    test('an offset east of UTC renders with a plus', () {
      final v = _binary(1266, _timetzBytes(9 * 3600 * 1000000, -4 * 3600));
      expect(decodeDriverValue(v), '09:00:00+04:00');
    });

    test('an offset west of UTC renders with a minus', () {
      final v = _binary(1266, _timetzBytes(13 * 3600 * 1000000, 5 * 3600));
      expect(decodeDriverValue(v), '13:00:00-05:00');
    });

    test('UTC renders as +00:00, not as a hex blob', () {
      final v = _binary(1266, _timetzBytes(0, 0));
      expect(decodeDriverValue(v), '00:00:00+00:00');
    });

    test('a half-hour zone keeps its minutes', () {
      final v = _binary(1266, _timetzBytes(0, -(5 * 3600 + 1800)));
      expect(decodeDriverValue(v), '00:00:00+05:30');
    });

    test('a wrong-length payload falls back rather than mis-decoding', () {
      final v = _binary(1266, [1, 2, 3]);
      expect(decodeDriverValue(v), isA<Uint8List>());
    });
  });

  group('decodeDriverValue — everything else', () {
    test('text-format bytes surface as a String', () {
      expect(decodeDriverValue(_text('hello')), 'hello');
    });

    test('binary UTF-8 with no control bytes surfaces as a String', () {
      // The citext case: valid text arriving on the binary wire.
      expect(decodeDriverValue(_binary(0, utf8.encode('café'))), 'café');
    });

    test('binary with a NUL surfaces as bytes', () {
      expect(
        decodeDriverValue(_binary(0, [0x89, 0x50, 0x00, 0x47])),
        isA<Uint8List>(),
      );
    });

    test('tab, LF and CR do not force the bytes path', () {
      expect(decodeDriverValue(_binary(0, utf8.encode('a\tb\nc\rd'))),
          'a\tb\nc\rd');
    });

    test('an already-decoded value passes through untouched', () {
      final now = DateTime(2026, 5, 23);
      expect(decodeDriverValue(now), same(now));
      expect(decodeDriverValue(42), 42);
      expect(decodeDriverValue(null), isNull);
    });
  });

  group('decodeDriverRow', () {
    test('preserves order and length', () {
      final row = decodeDriverRow([1, _text('x'), Time(1, 0, 0), null]);
      expect(row, [1, 'x', '01:00:00', null]);
    });
  });
}
