import 'dart:convert';

import 'package:postgres/postgres.dart';

/// Renders a raw cell value for display and editing.
///
/// The Postgres driver decodes `json`/`jsonb` columns into Dart [Map]/[List]
/// objects; `toString()` on those yields Dart's quote-less syntax, so they are
/// re-encoded as proper JSON instead. For types the driver doesn't have a
/// codec for (custom enums, citext, …) it hands back [UndecodedBytes]; those
/// are rendered via their text-format payload. Returns null for SQL NULL.
String? formatCellValue(dynamic value) {
  if (value == null) return null;

  if (value is UndecodedBytes) {
    if (value.isBinary) {
      final bytes = value.bytes;
      final preview =
          bytes.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      return '\\x$preview${bytes.length > 16 ? '…' : ''}';
    }
    return value.asString;
  }

  if (value is Map || value is List) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }

  return value.toString();
}
