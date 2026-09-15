import 'dart:typed_data';

import 'package:postgres/postgres.dart';

/// Converts a raw value coming back from the `postgres` driver into a
/// plain-Dart shape, so the layers above the service boundary never need
/// to import `package:postgres` just to inspect cell types.
///
/// The driver returns most types as concrete Dart values (int, double, bool,
/// BigInt, String, DateTime, Map, List). Types it doesn't have a codec for
/// (citext, custom enums, bytea, …) come back as [UndecodedBytes]:
///
///   - Text wire format → already textual; surfaced as String.
///   - Binary wire format with no sub-space control bytes → attempted as
///     text, falling back to a [Uint8List] when decoding fails.
///   - Binary wire format with control bytes (true bytea) → surfaced as
///     [Uint8List], to be rendered as a hex preview downstream.
Object? decodeDriverValue(Object? raw) {
  // `time` (OID 1083) decodes to the driver's own `Time`. Nothing above
  // this boundary knows that class: the grid would paint
  // `Time(09:00:00.000)` via `toString`, and the cell picker — which
  // handles `CellLiteral`, `DateTime` and `String` only — would fall
  // through to `DateTime.now()` and quietly offer to overwrite the stored
  // value with the current wall-clock time. Normalise to the same
  // `HH:MM:SS` text the picker parses and Postgres accepts back.
  if (raw is Time) return _timeText(raw.microseconds);

  if (raw is! UndecodedBytes) return raw;

  // `timetz` (OID 1266) has no codec at all. Its binary form is 8 bytes of
  // microseconds since midnight followed by a 4-byte zone offset in
  // seconds *west* of UTC. Left alone it trips the control-byte check and
  // paints as a hex blob.
  if (raw.isBinary && raw.typeOid == _timetzOid && raw.bytes.length == 12) {
    final view = ByteData.sublistView(raw.bytes);
    final micros = view.getInt64(0);
    final zoneSecondsWest = view.getInt32(8);
    return '${_timeText(micros)}${_zoneText(-zoneSecondsWest)}';
  }

  if (!raw.isBinary) {
    return raw.asString;
  }
  final bytes = raw.bytes;
  if (!_containsBinaryControlBytes(bytes)) {
    try {
      return raw.asString;
    } catch (_) {
      // fall through
    }
  }
  return Uint8List.fromList(bytes);
}

/// Decodes every cell of a Postgres driver row through [decodeDriverValue].
/// Lives next to the per-value decoder so both Postgres call sites
/// (`PostgresService.runQuery`, `PostgresTableRepository.fetchPage`) share
/// one implementation.
List<Object?> decodeDriverRow(List<Object?> raw) => [
  for (final v in raw) decodeDriverValue(v),
];

const int _timetzOid = 1266;

/// `HH:MM:SS`, with a fractional part only when there is one. Trailing
/// zeros are dropped so a whole second reads `09:00:00`, not
/// `09:00:00.000000`.
String _timeText(int microseconds) {
  final totalSeconds = microseconds ~/ Duration.microsecondsPerSecond;
  final frac = microseconds % Duration.microsecondsPerSecond;
  final h = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
  final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
  final s = (totalSeconds % 60).toString().padLeft(2, '0');
  if (frac == 0) return '$h:$m:$s';
  final f = frac.toString().padLeft(6, '0').replaceFirst(RegExp(r'0+$'), '');
  return '$h:$m:$s.$f';
}

/// `+HH:MM` / `-HH:MM` for an offset in seconds east of UTC.
String _zoneText(int secondsEast) {
  final sign = secondsEast < 0 ? '-' : '+';
  final abs = secondsEast.abs();
  final h = (abs ~/ 3600).toString().padLeft(2, '0');
  final m = ((abs % 3600) ~/ 60).toString().padLeft(2, '0');
  return '$sign$h:$m';
}

bool _containsBinaryControlBytes(List<int> bytes) {
  for (final b in bytes) {
    // Allow tab (9), LF (10), CR (13); reject any other sub-space control.
    if (b < 0x20 && b != 9 && b != 10 && b != 13) return true;
  }
  return false;
}
