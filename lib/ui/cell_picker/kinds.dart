import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// Discriminator on which kind of editor the picker should render.
enum KindId { text, bool, json, array, date, time, datetime }

/// Sizing + cosmetic config picked once per opened picker; the body widget
/// is dispatched on [id] separately.
class Kind {
  const Kind({
    required this.id,
    required this.label,
    required this.color,
    required this.size,
    this.withTimezone = false,
  });

  final KindId id;
  final String label;
  final Color color;
  final Size size;

  /// Whether to show a timezone input row — set for `*tz` Postgres types.
  final bool withTimezone;
}

// Regexes for numeric input — `FilteringTextInputFormatter.allow` runs
// per-character, so a digit-or-sign filter is enough to keep alpha out;
// validity of the assembled value falls to Postgres on apply.
final intFilter = FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]'));
final numberFilter = FilteringTextInputFormatter.allow(RegExp(r'[0-9\-+.eE]'));

// Each `_k*` below is a getter rather than a `final`: a top-level `final`
// resolves once per process, so its `color` would pin whichever palette was
// active when the first picker opened and never follow a dark ⇄ light swap.
// `kindFor` runs once per picker open, so rebuilding the record is free.

Kind get _kBool => Kind(
  id: KindId.bool,
  label: 'bool',
  color: AppColors.tBool,
  size: const Size(280, 118),
);
Kind get _kJson => Kind(
  id: KindId.json,
  label: 'json',
  color: AppColors.tJson,
  size: const Size(540, 340),
);
Kind get _kArray => Kind(
  id: KindId.array,
  label: 'array',
  color: AppColors.tJson,
  size: const Size(540, 340),
);
Kind get _kInt => Kind(
  id: KindId.text,
  label: 'int',
  color: AppColors.tNum,
  size: const Size(280, 120),
);
Kind get _kNumber => Kind(
  id: KindId.text,
  label: 'number',
  color: AppColors.tNum,
  size: const Size(280, 120),
);
// Sizes are the sum of the fixed parts: header 30 + footer 38 + 2 of
// border, plus the body — value line 36 + quick actions 32 for the moment
// kinds, and the calendar's 208 for date and datetime. The `*tz` datetime is
// wider for the zone field at the end of its value line; timetz fits at the
// base width.
Kind get _kDate => Kind(
  id: KindId.date,
  label: 'date',
  color: AppColors.tDate,
  size: const Size(280, 346),
);
Kind get _kTime => Kind(
  id: KindId.time,
  label: 'time',
  color: AppColors.tDate,
  size: const Size(280, 138),
);
Kind get _kTimeTz => Kind(
  id: KindId.time,
  label: 'timetz',
  color: AppColors.tDate,
  size: const Size(280, 138),
  withTimezone: true,
);
Kind get _kDatetime => Kind(
  id: KindId.datetime,
  label: 'timestamp',
  color: AppColors.tDate,
  size: const Size(280, 346),
);
Kind get _kDatetimeTz => Kind(
  id: KindId.datetime,
  label: 'timestamptz',
  color: AppColors.tDate,
  size: const Size(348, 346),
  withTimezone: true,
);
Kind get _kBytes => Kind(
  id: KindId.text,
  label: 'bytes',
  color: AppColors.textMuted,
  size: const Size(380, 200),
);
Kind get _kString => Kind(
  id: KindId.text,
  label: 'string',
  color: AppColors.tStr,
  size: const Size(380, 200),
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
