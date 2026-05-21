import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// Discriminator on which kind of editor the picker should render.
enum KindId { text, bool, json, date, time, datetime }

/// Sizing + cosmetic config picked once per opened picker; the body widget
/// is dispatched on [id] separately.
class Kind {
  const Kind({
    required this.id,
    required this.label,
    required this.color,
    required this.size,
    this.multiline = false,
    this.inputFormatters,
    this.withTimezone = false,
  });

  final KindId id;
  final String label;
  final Color color;
  final Size size;
  final bool multiline;
  final List<TextInputFormatter>? inputFormatters;

  /// Whether to show a timezone input row — set for `*tz` Postgres types.
  final bool withTimezone;
}

// Regexes for numeric input — `FilteringTextInputFormatter.allow` runs
// per-character, so a digit-or-sign filter is enough to keep alpha out;
// validity of the assembled value falls to Postgres on apply.
final intFilter = FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]'));
final numberFilter = FilteringTextInputFormatter.allow(RegExp(r'[0-9\-+.eE]'));

final _kBool = Kind(
  id: KindId.bool,
  label: 'bool',
  color: AppColors.tBool,
  size: const Size(296, 130),
);
final _kJson = Kind(
  id: KindId.json,
  label: 'json',
  color: AppColors.tJson,
  size: const Size(540, 340),
  multiline: true,
);
final _kArray = Kind(
  id: KindId.json,
  label: 'array',
  color: AppColors.tJson,
  size: const Size(540, 340),
  multiline: true,
);
final _kInt = Kind(
  id: KindId.text,
  label: 'int',
  color: AppColors.tNum,
  size: const Size(296, 132),
  inputFormatters: [intFilter],
);
final _kNumber = Kind(
  id: KindId.text,
  label: 'number',
  color: AppColors.tNum,
  size: const Size(296, 132),
  inputFormatters: [numberFilter],
);
// Widths and heights are sized to fit each picker's tightest constraint:
//   - Width: the footer's pill cluster (set NULL · DEFAULT · cancel · save ⌘↵
//     plus the optional `revert` chip) consistently wants ~290px before the
//     `kindHint` Expanded text collapses, so every date/time variant lives at
//     ≥ 296px; tz-bearing variants add room for the `@` punct + tz chip in
//     the mono value line.
//   - Height: header + value line + quick-actions row + body + footer must
//     all fit without `Expanded` having to crush the calendar's fixed 30px
//     rows. Datetime's body is just the calendar (~242) — h/m/s editing
//     happens via the value-line segments above. The tz variant adds ~50 for
//     a divider + TZ input row beneath the calendar.
final _kDate = Kind(
  id: KindId.date,
  label: 'date',
  color: AppColors.tDate,
  size: const Size(296, 384),
);
final _kTime = Kind(
  id: KindId.time,
  label: 'time',
  color: AppColors.tDate,
  size: const Size(296, 200),
);
final _kTimeTz = Kind(
  id: KindId.time,
  label: 'timetz',
  color: AppColors.tDate,
  size: const Size(320, 240),
  withTimezone: true,
);
final _kDatetime = Kind(
  id: KindId.datetime,
  label: 'timestamp',
  color: AppColors.tDate,
  size: const Size(320, 400),
);
final _kDatetimeTz = Kind(
  id: KindId.datetime,
  label: 'timestamptz',
  color: AppColors.tDate,
  size: const Size(340, 460),
  withTimezone: true,
);
final _kBytes = Kind(
  id: KindId.text,
  label: 'bytes',
  color: AppColors.textMuted,
  size: const Size(380, 220),
  multiline: true,
);
final _kString = Kind(
  id: KindId.text,
  label: 'string',
  color: AppColors.tStr,
  size: const Size(380, 220),
  multiline: true,
);

/// Picks a picker shape. The column's `dataType` (from the catalog) is the
/// authoritative source — falls back to the runtime value's class when the
/// caller doesn't have catalog metadata yet.
Kind kindFor(Object? v, String? dataType) {
  if (dataType != null) {
    final byType = _kindForDataType(dataType.toLowerCase());
    if (byType != null) return byType;
  }
  return _kindForValue(v);
}

Kind? _kindForDataType(String dt) {
  final hasTz = dt.contains('with time zone');
  if (dt == 'date') return _kDate;
  if (dt.startsWith('timestamp')) {
    return hasTz || dt == 'timestamptz' ? _kDatetimeTz : _kDatetime;
  }
  if (dt.startsWith('time')) return hasTz || dt == 'timetz' ? _kTimeTz : _kTime;
  if (dt == 'boolean') return _kBool;
  if (dt == 'json' || dt == 'jsonb') return _kJson;
  if (dt == 'array' || dt.endsWith('[]')) return _kArray;
  if (dt.contains('int') || dt == 'serial') return _kInt;
  if (const {'numeric', 'decimal', 'real', 'double precision'}.contains(dt)) {
    return _kNumber;
  }
  if (dt == 'bytea') return _kBytes;
  return null;
}

Kind _kindForValue(Object? v) => switch (v) {
  bool() => _kBool,
  Map() => _kJson,
  // Uint8List implements List<int>, so it must precede the generic List case.
  Uint8List() => _kBytes,
  List() => _kArray,
  BigInt() => _kInt,
  int() => _kInt,
  num() => _kNumber,
  DateTime() => _kDatetime,
  _ => _kString,
};
