import 'dart:convert';
import 'dart:typed_data';

import '../services/sql_identifier.dart';

/// Renders a raw cell value for display and editing.
///
/// All driver-specific decoding (UndecodedBytes → String or Uint8List)
/// happens at the service boundary in [decodeDriverValue], so this layer
/// only sees standard Dart types: primitives, [DateTime], [Map]/[List]
/// for JSON, and [Uint8List] for binary blobs. Returns null for SQL NULL.
String? formatCellValue(Object? value) {
  if (value == null) return null;

  if (value is Uint8List) return _hex(value, cap: _previewBytes);

  // ISO-8601 (with offset for UTC, naive otherwise) matches the form the
  // cell editor parses back via DateTime.tryParse in editor_state.dart, so
  // a value round-tripped through display → re-edit doesn't change shape.
  if (value is DateTime) return value.toIso8601String();

  if (value is Map || value is List) {
    return jsonEncode(value, toEncodable: _encodeForJson);
  }

  return value.toString();
}

/// Fallback encoder for `jsonEncode`. Handles [DateTime] (nested inside a
/// Map/List) as ISO-8601 to match the top-level [DateTime] branch above;
/// any other type that the default encoder can't serialise degrades to
/// its `toString()` so a single odd value can't produce invalid JSON.
Object? _encodeForJson(Object? value) {
  if (value is DateTime) return value.toIso8601String();
  return value.toString();
}

/// Exact text for a cell value, for consumers that hand the value onward
/// rather than paint it: file export, clipboard copy.
///
/// Identical to [formatCellValue] except for binary, where the display form
/// is an elided 16-byte preview. Writing that preview into a CSV or onto the
/// clipboard would pass off the first 16 bytes of a blob as the whole thing.
String? exactCellValue(Object? value) {
  if (value is Uint8List) return _hex(value, cap: null);
  return formatCellValue(value);
}

/// How many bytes of a binary value the grid paints before eliding. A cell
/// is one ellipsized line; the full blob can be megabytes.
const int _previewBytes = 16;

String _hex(Uint8List bytes, {required int? cap}) {
  final shown = cap == null ? bytes : bytes.take(cap);
  final hex = shown.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final elided = cap != null && bytes.length > cap;
  return '\\x$hex${elided ? '…' : ''}';
}

/// Renders `"column" = value` (or `!=`, `IS NULL`, `IS NOT NULL`) suitable
/// for splicing into a WHERE clause. Numerics and booleans go in
/// unquoted; everything else flows through [formatCellValue] and gets its
/// single quotes doubled. The column identifier is escaped via
/// [quoteIdent] so a column literally named `weird"name` is handled.
String equalityFragment(String column, Object? value, {bool not = false}) {
  final ident = quoteIdent(column);
  if (value == null) return '$ident IS ${not ? 'NOT ' : ''}NULL';
  final op = not ? '!=' : '=';
  if (value is num || value is BigInt || value is bool) {
    return '$ident $op $value';
  }
  final text = formatCellValue(value) ?? '';
  return "$ident $op '${text.replaceAll("'", "''")}'";
}
