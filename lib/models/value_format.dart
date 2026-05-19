import 'dart:convert';
import 'dart:typed_data';

import 'package:postgres/postgres.dart';

/// Renders a raw cell value for display and editing.
///
/// The Postgres driver decodes `json`/`jsonb` columns into Dart [Map]/[List]
/// objects; `toString()` on those yields Dart's quote-less syntax, so they are
/// re-encoded as proper JSON instead. For types the driver doesn't have a
/// codec for (custom enums, citext, …) it hands back [UndecodedBytes]; those
/// are decoded as text when the bytes look textual, and rendered as a hex
/// preview only when they contain real binary content (bytea). Returns null
/// for SQL NULL.
String? formatCellValue(dynamic value) {
  if (value == null) return null;

  if (value is UndecodedBytes) {
    // Text wire format → already text.
    if (!value.isBinary) return value.asString;

    // Binary wire format. Most custom text types (citext, ltree, custom
    // enums, …) arrive here even though their bytes are valid UTF-8. Try a
    // text decode first; only fall back to hex when bytes contain real
    // binary control characters that suggest bytea or similar.
    final bytes = value.bytes;
    if (!_containsBinaryControlBytes(bytes)) {
      try {
        return value.asString;
      } catch (_) {
        // fall through to hex
      }
    }
    return _hexPreview(bytes);
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

bool _containsBinaryControlBytes(Uint8List bytes) {
  for (final b in bytes) {
    // Allow tab (9), LF (10), CR (13); reject any other sub-space control.
    if (b < 0x20 && b != 9 && b != 10 && b != 13) return true;
  }
  return false;
}

String _hexPreview(Uint8List bytes) {
  final preview =
      bytes.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '\\x$preview${bytes.length > 16 ? '…' : ''}';
}
