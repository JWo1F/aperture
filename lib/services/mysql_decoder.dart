import 'dart:convert';
import 'dart:typed_data';

import 'package:mysql_dart/mysql_protocol.dart' show MySQLColumnType;

import 'driver_decoder.dart';

/// Converts a cell from `mysql_dart`'s text protocol into the plain-Dart
/// shape the layers above the service boundary expect.
///
/// The text protocol delivers every value as a `String`, except blob-family
/// columns flagged binary and `BIT` / `GEOMETRY`, which arrive as
/// [Uint8List]. The column type decides the rest:
///
///   - integers become `int`, or `BigInt` past 2^63 (`BIGINT UNSIGNED`)
///   - `FLOAT` / `DOUBLE` become `double`
///   - `DECIMAL` stays text, so no precision is lost on the way to the grid
///   - `JSON` is decoded to a `Map` / `List`, like a Postgres `jsonb`
///   - `BIT` becomes the integer it spells
///   - dates and times stay as the server printed them, which is also the
///     form it accepts back
///   - blob bytes that read as text become a `String`. MariaDB's `JSON` is
///     a `LONGTEXT` with a binary collation, and so is any `TEXT` column
///     with a `_bin` collation; both carry the binary flag.
Object? decodeMysqlValue(Object? raw, MySQLColumnType type) {
  if (raw == null) return null;
  final code = type.intVal;
  if (raw is Uint8List) {
    if (code == MySQLColumnType.bitType.intVal) return _bitValue(raw);
    if (code == MySQLColumnType.geometryType.intVal) return raw;
    if (!containsBinaryControlBytes(raw)) {
      try {
        return utf8.decode(raw);
      } on FormatException {
        return raw;
      }
    }
    return raw;
  }
  if (raw is! String) return raw;
  if (_integerTypes.contains(code)) {
    return int.tryParse(raw) ?? BigInt.tryParse(raw) ?? raw;
  }
  if (code == MySQLColumnType.floatType.intVal ||
      code == MySQLColumnType.doubleType.intVal) {
    return double.tryParse(raw) ?? raw;
  }
  if (code == MySQLColumnType.jsonType.intVal) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      return raw;
    }
  }
  return raw;
}

final Set<int> _integerTypes = {
  MySQLColumnType.tinyType.intVal,
  MySQLColumnType.shortType.intVal,
  MySQLColumnType.int24Type.intVal,
  MySQLColumnType.longType.intVal,
  MySQLColumnType.longLongType.intVal,
  MySQLColumnType.yearType.intVal,
};

/// A `BIT(n)` value is its bytes read big-endian.
Object _bitValue(Uint8List bytes) {
  var value = BigInt.zero;
  for (final b in bytes) {
    value = (value << 8) | BigInt.from(b);
  }
  return value.isValidInt ? value.toInt() : value;
}
