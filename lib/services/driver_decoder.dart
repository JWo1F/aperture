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
  if (raw is! UndecodedBytes) return raw;
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

bool _containsBinaryControlBytes(List<int> bytes) {
  for (final b in bytes) {
    // Allow tab (9), LF (10), CR (13); reject any other sub-space control.
    if (b < 0x20 && b != 9 && b != 10 && b != 13) return true;
  }
  return false;
}
