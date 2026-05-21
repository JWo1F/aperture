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

  if (value is Uint8List) return _hexPreview(value);

  if (value is Map || value is List) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }

  return value.toString();
}

String _hexPreview(Uint8List bytes) {
  final preview = bytes
      .take(16)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '\\x$preview${bytes.length > 16 ? '…' : ''}';
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
