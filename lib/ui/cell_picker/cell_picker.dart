import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../widgets/code_editor.dart';
import '../widgets/common.dart';

/// Opens an overlay editor anchored to the cell's top-left corner. The shape
/// of the picker depends on the value type — text grows multi-line, JSON gets
/// syntax highlighting + room, booleans become a two-button toggle, dates
/// show a calendar, times show an HH:MM:SS spinner, datetimes combine both.
///
/// Set NULL / Set DEFAULT are disabled when the column metadata forbids
/// them (via [canBeNull] / [hasDefault]).
void showCellPicker(
  BuildContext context, {
  required Rect anchorRect,
  required String columnName,
  required Object? originalValue,
  required CellEditValue? pendingEdit,
  required ValueChanged<CellEditValue> onCommit,
  VoidCallback? onRevert,
  bool canBeNull = true,
  bool hasDefault = false,
  String? columnDataType,
  bool isPrimaryKey = false,
  bool isForeignKey = false,
}) {
  final kind = _kindFor(originalValue, columnDataType);
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  void close() {
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => _PickerOverlay(
      kind: kind,
      anchorRect: anchorRect,
      columnName: columnName,
      originalValue: originalValue,
      pendingEdit: pendingEdit,
      canBeNull: canBeNull,
      hasDefault: hasDefault,
      columnDataType: columnDataType,
      isPrimaryKey: isPrimaryKey,
      isForeignKey: isForeignKey,
      onCommit: (value) {
        close();
        onCommit(value);
      },
      onRevert: onRevert == null
          ? null
          : () {
              close();
              onRevert();
            },
      onClose: close,
    ),
  );

  overlay.insert(entry);
}

// --- Kinds -------------------------------------------------------------

enum _KindId { text, bool, json, date, time, datetime }

class _Kind {
  const _Kind({
    required this.id,
    required this.label,
    required this.color,
    required this.size,
    this.multiline = false,
    this.inputFormatters,
    this.withTimezone = false,
  });

  final _KindId id;
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
final _intFilter =
    FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]'));
final _numberFilter =
    FilteringTextInputFormatter.allow(RegExp(r'[0-9\-+.eE]'));

final _kBool = _Kind(
  id: _KindId.bool,
  label: 'bool',
  color: AppColors.tBool,
  size: const Size(296, 130),
);
final _kJson = _Kind(
  id: _KindId.json,
  label: 'json',
  color: AppColors.tJson,
  size: const Size(540, 340),
  multiline: true,
);
final _kArray = _Kind(
  id: _KindId.json,
  label: 'array',
  color: AppColors.tJson,
  size: const Size(540, 340),
  multiline: true,
);
final _kInt = _Kind(
  id: _KindId.text,
  label: 'int',
  color: AppColors.tNum,
  size: const Size(296, 132),
  inputFormatters: [_intFilter],
);
final _kNumber = _Kind(
  id: _KindId.text,
  label: 'number',
  color: AppColors.tNum,
  size: const Size(296, 132),
  inputFormatters: [_numberFilter],
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
final _kDate = _Kind(
  id: _KindId.date,
  label: 'date',
  color: AppColors.tDate,
  size: const Size(296, 384),
);
final _kTime = _Kind(
  id: _KindId.time,
  label: 'time',
  color: AppColors.tDate,
  size: const Size(296, 200),
);
final _kTimeTz = _Kind(
  id: _KindId.time,
  label: 'timetz',
  color: AppColors.tDate,
  size: const Size(320, 240),
  withTimezone: true,
);
final _kDatetime = _Kind(
  id: _KindId.datetime,
  label: 'timestamp',
  color: AppColors.tDate,
  size: const Size(320, 400),
);
final _kDatetimeTz = _Kind(
  id: _KindId.datetime,
  label: 'timestamptz',
  color: AppColors.tDate,
  size: const Size(340, 460),
  withTimezone: true,
);
final _kBytes = _Kind(
  id: _KindId.text,
  label: 'bytes',
  color: AppColors.textMuted,
  size: const Size(380, 220),
  multiline: true,
);
final _kString = _Kind(
  id: _KindId.text,
  label: 'string',
  color: AppColors.tStr,
  size: const Size(380, 220),
  multiline: true,
);

/// Picks a picker shape. The column's `dataType` (from the catalog) is the
/// authoritative source — falls back to the runtime value's class when the
/// caller doesn't have catalog metadata yet.
_Kind _kindFor(Object? v, String? dataType) {
  if (dataType != null) {
    final dt = dataType.toLowerCase();
    if (dt == 'date') return _kDate;
    if (dt.startsWith('timestamp')) {
      return dt.contains('with time zone') || dt == 'timestamptz'
          ? _kDatetimeTz
          : _kDatetime;
    }
    if (dt.startsWith('time')) {
      return dt.contains('with time zone') || dt == 'timetz'
          ? _kTimeTz
          : _kTime;
    }
    if (dt == 'boolean') return _kBool;
    if (dt == 'json' || dt == 'jsonb') return _kJson;
    if (dt == 'array' || dt.endsWith('[]')) return _kArray;
    if (dt.contains('int') ||
        dt == 'smallint' ||
        dt == 'bigint' ||
        dt == 'serial') {
      return _kInt;
    }
    if (dt == 'numeric' ||
        dt == 'decimal' ||
        dt == 'real' ||
        dt == 'double precision') {
      return _kNumber;
    }
    if (dt == 'bytea') return _kBytes;
    // Fall through to runtime-type inspection for unknown types.
  }
  if (v is bool) return _kBool;
  if (v is Map) return _kJson;
  if (v is List) return _kArray;
  if (v is int || v is BigInt) return _kInt;
  if (v is num) return _kNumber;
  if (v is DateTime) return _kDatetime;
  if (v is Uint8List) return _kBytes;
  return _kString;
}

// --- Initial state extraction -----------------------------------------

String _initialText(Object? raw, CellEditValue? pending) {
  if (pending is CellLiteral) return pending.value ?? '';
  if (pending is CellDefault) return '';
  if (raw == null) return '';
  if (raw is Map || raw is List) {
    try {
      return const JsonEncoder.withIndent('  ').convert(raw);
    } catch (_) {
      return raw.toString();
    }
  }
  if (raw is Uint8List) return '';
  if (raw is DateTime) return raw.toIso8601String();
  return raw.toString();
}

bool? _initialBool(Object? raw, CellEditValue? pending) {
  if (pending is CellLiteral) {
    if (pending.value == null) return null;
    final v = pending.value!.toLowerCase();
    if (v == 'true' || v == 't' || v == '1') return true;
    if (v == 'false' || v == 'f' || v == '0') return false;
    return null;
  }
  if (raw is bool) return raw;
  return null;
}

DateTime _initialMoment(Object? raw, CellEditValue? pending) {
  if (pending is CellLiteral) {
    final s = pending.value;
    if (s != null && s.isNotEmpty) {
      final parsed = DateTime.tryParse(s);
      if (parsed != null) return parsed;
      // Try time-only "HH:MM:SS(.mmm)?(<space>tz)?"
      final tm = RegExp(
        r'^(\d{1,2}):(\d{1,2})(?::(\d{1,2})(?:\.(\d{1,3}))?)?',
      ).firstMatch(s);
      if (tm != null) {
        final h = int.parse(tm.group(1)!);
        final m = int.parse(tm.group(2)!);
        final sec = int.parse(tm.group(3) ?? '0');
        final msStr = tm.group(4);
        final ms = msStr == null
            ? 0
            : int.parse(msStr.padRight(3, '0').substring(0, 3));
        return DateTime(1970, 1, 1, h, m, sec, ms);
      }
    }
  }
  if (raw is DateTime) return raw;
  if (raw is String) {
    final p = DateTime.tryParse(raw);
    if (p != null) return p;
  }
  return DateTime.now();
}

/// Extracts a trailing timezone hint from a pending literal so re-opening a
/// staged edit pre-fills the TZ field. Falls back to empty (server default).
String _initialTz(Object? raw, CellEditValue? pending) {
  if (pending is CellLiteral) {
    final s = pending.value;
    if (s != null) {
      final m = RegExp(r'(?:[+-]\d{2}(?::?\d{2})?|\b[A-Z][A-Za-z_/+\-0-9]{1,})$')
          .firstMatch(s.trim());
      if (m != null) {
        final hit = m.group(0)!;
        // Don't mistake the date's first 4-digit year for a tz.
        if (hit.length >= 2 && !RegExp(r'^\d').hasMatch(hit)) return hit;
      }
    }
  }
  return '';
}

// --- Overlay -----------------------------------------------------------

class _PickerOverlay extends StatelessWidget {
  const _PickerOverlay({
    required this.kind,
    required this.anchorRect,
    required this.columnName,
    required this.originalValue,
    required this.pendingEdit,
    required this.canBeNull,
    required this.hasDefault,
    required this.columnDataType,
    required this.isPrimaryKey,
    required this.isForeignKey,
    required this.onCommit,
    required this.onRevert,
    required this.onClose,
  });

  final _Kind kind;
  final Rect anchorRect;
  final String columnName;
  final Object? originalValue;
  final CellEditValue? pendingEdit;
  final bool canBeNull;
  final bool hasDefault;
  final String? columnDataType;
  final bool isPrimaryKey;
  final bool isForeignKey;
  final ValueChanged<CellEditValue> onCommit;
  final VoidCallback? onRevert;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    var x = anchorRect.left;
    var y = anchorRect.top;
    final w = kind.size.width;
    final h = kind.size.height;
    if (x + w + 8 > media.width) x = media.width - w - 8;
    if (y + h + 8 > media.height) y = media.height - h - 8;
    if (x < 8) x = 8;
    if (y < 8) y = 8;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            onSecondaryTap: onClose,
          ),
        ),
        Positioned(
          left: x,
          top: y,
          width: w,
          height: h,
          child: _Panel(
            kind: kind,
            columnName: columnName,
            originalValue: originalValue,
            pendingEdit: pendingEdit,
            canBeNull: canBeNull,
            hasDefault: hasDefault,
            columnDataType: columnDataType,
            isPrimaryKey: isPrimaryKey,
            isForeignKey: isForeignKey,
            onCommit: onCommit,
            onRevert: onRevert,
            onClose: onClose,
          ),
        ),
      ],
    );
  }
}

// --- Panel -------------------------------------------------------------

class _Panel extends StatefulWidget {
  const _Panel({
    required this.kind,
    required this.columnName,
    required this.originalValue,
    required this.pendingEdit,
    required this.canBeNull,
    required this.hasDefault,
    required this.columnDataType,
    required this.isPrimaryKey,
    required this.isForeignKey,
    required this.onCommit,
    required this.onRevert,
    required this.onClose,
  });

  final _Kind kind;
  final String columnName;
  final Object? originalValue;
  final CellEditValue? pendingEdit;
  final bool canBeNull;
  final bool hasDefault;
  final String? columnDataType;
  final bool isPrimaryKey;
  final bool isForeignKey;
  final ValueChanged<CellEditValue> onCommit;
  final VoidCallback? onRevert;
  final VoidCallback onClose;

  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  // Text/JSON-only state
  TextEditingController? _text;
  late String _baselineText;
  String? _jsonError;

  // Bool-only state
  bool? _bool;
  bool? _baselineBool;

  // Date/time/datetime state
  DateTime? _moment;
  DateTime? _baselineMoment;
  // Bumped whenever Now/Today resets the moment; passed as a Key to the
  // time/calendar sub-widgets so they refresh their internal state without
  // losing the cursor during normal user typing.
  int _resetTick = 0;

  // Timezone (only relevant when widget.kind.withTimezone)
  String _tz = '';
  String _baselineTz = '';

  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    final k = widget.kind.id;
    switch (k) {
      case _KindId.bool:
        _baselineBool =
            _initialBool(widget.originalValue, widget.pendingEdit);
        _bool = _baselineBool;
      case _KindId.date:
      case _KindId.time:
      case _KindId.datetime:
        _baselineMoment =
            _initialMoment(widget.originalValue, widget.pendingEdit);
        _moment = _baselineMoment;
        if (widget.kind.withTimezone) {
          _baselineTz = _initialTz(widget.originalValue, widget.pendingEdit);
          _tz = _baselineTz;
        }
      case _KindId.text:
      case _KindId.json:
        _baselineText =
            _initialText(widget.originalValue, widget.pendingEdit);
        _text = k == _KindId.json
            ? CodeEditorController(text: _baselineText, language: 'json')
            : TextEditingController(text: _baselineText);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focus.requestFocus();
        });
    }
  }

  @override
  void dispose() {
    _text?.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _isDirty {
    switch (widget.kind.id) {
      case _KindId.bool:
        return _bool != _baselineBool;
      case _KindId.date:
      case _KindId.time:
      case _KindId.datetime:
        if (_moment != _baselineMoment) return true;
        if (widget.kind.withTimezone && _tz != _baselineTz) return true;
        return false;
      case _KindId.text:
      case _KindId.json:
        return _text!.text != _baselineText;
    }
  }

  void _save() {
    switch (widget.kind.id) {
      case _KindId.bool:
        if (_bool == null) return;
        widget.onCommit(CellLiteral(_bool! ? 'true' : 'false'));
      case _KindId.date:
        widget.onCommit(CellLiteral(_formatDate(_moment!)));
      case _KindId.time:
        widget.onCommit(CellLiteral(
          _formatTime(_moment!, tz: widget.kind.withTimezone ? _tz : null),
        ));
      case _KindId.datetime:
        widget.onCommit(CellLiteral(
          _formatDateTime(_moment!, tz: widget.kind.withTimezone ? _tz : null),
        ));
      case _KindId.json:
        // Validate before committing — empty input is allowed (and means
        // "send the empty string", e.g. for an empty jsonb column).
        final text = _text!.text;
        if (text.trim().isNotEmpty) {
          try {
            jsonDecode(text);
          } catch (e) {
            setState(() => _jsonError = _shortJsonError(e));
            return;
          }
        }
        setState(() => _jsonError = null);
        widget.onCommit(CellLiteral(text));
      case _KindId.text:
        widget.onCommit(CellLiteral(_text!.text));
    }
  }

  String _shortJsonError(Object e) {
    // FormatException messages are usually "FormatException: <msg>". Strip
    // the prefix for a cleaner inline error.
    final s = e.toString();
    const prefix = 'FormatException: ';
    if (s.startsWith(prefix)) return s.substring(prefix.length);
    return s;
  }

  void _setNull() => widget.onCommit(const CellLiteral(null));
  void _setDefault() => widget.onCommit(const CellDefault());

  /// Footer hint string, mirroring the design's `.ce-hint`: commit affordance
  /// changes for one-line kinds (Enter commits) vs multi-line / picker kinds
  /// (⌘↵ commits).
  String _footerHint() {
    if (widget.isPrimaryKey) return 'cannot edit primary key';
    switch (widget.kind.id) {
      case _KindId.text:
        return '↵ commit · esc cancel';
      case _KindId.bool:
        return 'esc cancel';
      case _KindId.json:
      case _KindId.date:
      case _KindId.time:
      case _KindId.datetime:
        return '⌘↵ commit · esc cancel';
    }
  }

  /// Resets the time/date state to "now". Bumps [_resetTick] so the calendar
  /// + time-input rebuild from scratch and reflect the new value, even if
  /// they're stateful with internal controllers.
  void _setToNow() {
    setState(() {
      _moment = DateTime.now();
      if (widget.kind.withTimezone) _tz = '';
      _resetTick++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _save,
      },
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.accent, width: 1.5),
            boxShadow: [
              const BoxShadow(
                color: Color(0x66000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
              BoxShadow(
                color: AppColors.accentSoft,
                blurRadius: 0,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                columnName: widget.columnName,
                kind: widget.kind,
                pendingEdit: widget.pendingEdit,
                columnDataType: widget.columnDataType,
                isPrimaryKey: widget.isPrimaryKey,
                isForeignKey: widget.isForeignKey,
              ),
              Expanded(child: _buildBody()),
              _Footer(
                hasPending: widget.pendingEdit != null,
                canSave: _isDirty,
                canBeNull: widget.canBeNull,
                hasDefault: widget.hasDefault,
                kindHint: _footerHint(),
                onSave: _save,
                onCancel: widget.onClose,
                onSetNull: _setNull,
                onSetDefault: _setDefault,
                onRevert: widget.onRevert,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _shiftDate({int days = 0}) {
    setState(() {
      final m = _moment ?? DateTime.now();
      _moment = m.add(Duration(days: days));
      _resetTick++;
    });
  }

  void _shiftHour({int hours = 0}) {
    setState(() {
      final m = _moment ?? DateTime.now();
      _moment = m.add(Duration(hours: hours));
      _resetTick++;
    });
  }

  void _roundHour() {
    setState(() {
      final m = _moment ?? DateTime.now();
      _moment = DateTime(m.year, m.month, m.day, m.hour);
      _resetTick++;
    });
  }

  void _setToday({bool zeroTime = false}) {
    setState(() {
      final n = DateTime.now();
      final m = _moment ?? n;
      _moment = zeroTime
          ? DateTime(n.year, n.month, n.day)
          : DateTime(n.year, n.month, n.day, m.hour, m.minute, m.second,
              m.millisecond);
      _resetTick++;
    });
  }

  Widget _buildBody() {
    switch (widget.kind.id) {
      case _KindId.bool:
        return _BoolBody(
          value: _bool,
          onChange: (v) => setState(() => _bool = v),
          onNull: () => widget.onCommit(const CellLiteral(null)),
        );
      case _KindId.date:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MonoValueLine(
              kind: _KindId.date,
              moment: _moment!,
              tz: _tz,
              withTz: false,
              onChange: (dt) => setState(() => _moment = dt),
              onTzChange: (_) {},
            ),
            _QuickActionsRow(
              children: [
                _QuickAction(
                  label: 'Today',
                  icon: Icons.today_outlined,
                  primary: true,
                  onTap: () => _setToday(zeroTime: true),
                ),
                _QuickAction(
                  label: '−1 day',
                  onTap: () => _shiftDate(days: -1),
                ),
                _QuickAction(
                  label: '+1 day',
                  onTap: () => _shiftDate(days: 1),
                ),
              ],
            ),
            Expanded(
              child: _CalendarBody(
                initial: _moment!,
                resetTick: _resetTick,
                onChange: (d) => setState(() {
                  _moment = DateTime(d.year, d.month, d.day);
                }),
              ),
            ),
          ],
        );
      case _KindId.time:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MonoValueLine(
              kind: _KindId.time,
              moment: _moment!,
              tz: _tz,
              withTz: widget.kind.withTimezone,
              onChange: (dt) => setState(() => _moment = dt),
              onTzChange: (tz) => setState(() => _tz = tz),
            ),
            _QuickActionsRow(
              children: [
                _QuickAction(
                  label: 'Now',
                  icon: Icons.bolt,
                  primary: true,
                  onTap: _setToNow,
                ),
                _QuickAction(
                  label: 'round :00',
                  onTap: _roundHour,
                ),
                _QuickAction(
                  label: '+1 hour',
                  onTap: () => _shiftHour(hours: 1),
                ),
              ],
            ),
            Expanded(
              child: _TimeBody(
                initial: _moment!,
                withTz: widget.kind.withTimezone,
                tz: _tz,
                resetTick: _resetTick,
                onChange: (h, m, s, ms) => setState(() {
                  _moment = DateTime(1970, 1, 1, h, m, s, ms);
                }),
                onTzChange: (tz) => setState(() => _tz = tz),
              ),
            ),
          ],
        );
      case _KindId.datetime:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MonoValueLine(
              kind: _KindId.datetime,
              moment: _moment!,
              tz: _tz,
              withTz: widget.kind.withTimezone,
              onChange: (dt) => setState(() => _moment = dt),
              onTzChange: (tz) => setState(() => _tz = tz),
            ),
            _QuickActionsRow(
              children: [
                _QuickAction(
                  label: 'Now',
                  icon: Icons.bolt,
                  primary: true,
                  onTap: _setToNow,
                ),
                _QuickAction(
                  label: 'Today 00:00',
                  onTap: () => _setToday(zeroTime: true),
                ),
                _QuickAction(
                  label: 'Tomorrow',
                  onTap: () => _shiftDate(days: 1),
                ),
              ],
            ),
            Expanded(
              child: _DateTimeBody(
                initial: _moment!,
                withTz: widget.kind.withTimezone,
                tz: _tz,
                resetTick: _resetTick,
                onChange: (dt) => setState(() => _moment = dt),
                onTzChange: (tz) => setState(() => _tz = tz),
              ),
            ),
          ],
        );
      case _KindId.text:
      case _KindId.json:
        final isNumber = widget.kind.label == 'number' ||
            widget.kind.label == 'int';
        if (isNumber) {
          return _NumberBody(
            controller: _text!,
            focus: _focus,
            intOnly: widget.kind.label == 'int',
            onChanged: () => setState(() {}),
          );
        }
        return _TextBody(
          controller: _text!,
          focus: _focus,
          multiline: widget.kind.multiline,
          onChanged: () => setState(() {
            // Clear the stale JSON error as soon as the user starts typing.
            if (_jsonError != null) _jsonError = null;
          }),
          inputFormatters: widget.kind.inputFormatters,
          error: widget.kind.id == _KindId.json ? _jsonError : null,
        );
    }
  }
}

String _pad(int n) => n.toString().padLeft(2, '0');
String _pad3(int n) => n.toString().padLeft(3, '0');
String _formatDate(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';
String _formatTime(DateTime d, {String? tz}) {
  final base = '${_pad(d.hour)}:${_pad(d.minute)}:${_pad(d.second)}'
      '.${_pad3(d.millisecond)}';
  final t = tz?.trim() ?? '';
  return t.isEmpty ? base : '$base $t';
}

String _formatDateTime(DateTime d, {String? tz}) =>
    '${_formatDate(d)} ${_formatTime(d, tz: tz)}';

// --- Header / Footer ---------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.columnName,
    required this.kind,
    required this.pendingEdit,
    required this.columnDataType,
    required this.isPrimaryKey,
    required this.isForeignKey,
  });

  final String columnName;
  final _Kind kind;
  final CellEditValue? pendingEdit;
  final String? columnDataType;
  final bool isPrimaryKey;
  final bool isForeignKey;

  ({String label, Color color})? _flag() {
    if (isPrimaryKey) return (label: 'read-only', color: AppColors.warn);
    return switch (pendingEdit) {
      CellLiteral(:final value) when value == null =>
        (label: 'NULL', color: AppColors.accent),
      CellLiteral() => (label: 'edited', color: AppColors.accent),
      CellDefault() => (label: 'DEFAULT', color: AppColors.accent),
      null => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final flag = _flag();
    final typeLabel = columnDataType ?? kind.label;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Row(
        children: [
          if (isPrimaryKey) ...[
            Icon(Icons.vpn_key, size: 10, color: AppColors.accent),
            const SizedBox(width: 6),
          ] else if (isForeignKey) ...[
            Icon(Icons.north_east, size: 10, color: AppColors.tFk),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              columnName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.mono(
                size: 10.5,
                color: AppColors.textPrimary,
                weight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              typeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.mono(
                size: 10.5,
                color: AppColors.textMuted,
              ),
            ),
          ),
          if (flag != null) ...[
            const Spacer(),
            Text(
              flag.label,
              style: AppTheme.mono(
                size: 10,
                color: flag.color,
                weight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.hasPending,
    required this.canSave,
    required this.canBeNull,
    required this.hasDefault,
    required this.kindHint,
    required this.onSave,
    required this.onCancel,
    required this.onSetNull,
    required this.onSetDefault,
    required this.onRevert,
  });

  final bool hasPending;
  final bool canSave;
  final bool canBeNull;
  final bool hasDefault;
  final String kindHint;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final VoidCallback onSetNull;
  final VoidCallback onSetDefault;
  final VoidCallback? onRevert;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              kindHint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.mono(
                size: 10.5,
                color: AppColors.textMuted,
              ),
            ),
          ),
          if (hasPending) ...[
            _PillButton(
              label: 'revert',
              onPressed: onRevert,
            ),
            const SizedBox(width: 4),
          ],
          _PillButton(
            label: 'set NULL',
            disabled: !canBeNull,
            onPressed: canBeNull ? onSetNull : null,
          ),
          const SizedBox(width: 4),
          _PillButton(
            label: 'DEFAULT',
            disabled: !hasDefault,
            onPressed: hasDefault ? onSetDefault : null,
          ),
          const SizedBox(width: 6),
          _PillButton(
            label: 'cancel',
            onPressed: onCancel,
          ),
          const SizedBox(width: 4),
          _PillButton(
            label: 'save  ⌘↵',
            primary: true,
            onPressed: canSave ? onSave : null,
          ),
        ],
      ),
    );
  }
}

/// Small mono pill button used in the cell editor footer for set NULL /
/// DEFAULT / cancel / save. Primary variant lights the accent.
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.onPressed,
    this.disabled = false,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool disabled;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !disabled;
    return Hoverable(
      cursor:
          enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onTap: enabled ? onPressed : null,
      builder: (context, hovering) {
        final Color bg = primary
            ? (enabled
                ? (hovering ? AppColors.accentHover : AppColors.accent)
                : AppColors.accent.withValues(alpha: 0.4))
            : (hovering && enabled
                ? AppColors.surfaceHover
                : Colors.transparent);
        final Color border = primary
            ? Colors.transparent
            : (enabled ? AppColors.border : AppColors.border);
        final Color fg = primary
            ? Colors.white
            : (enabled
                ? (hovering
                    ? AppColors.textPrimary
                    : AppColors.textSecondary)
                : AppColors.text4);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: border),
          ),
          child: Text(
            label,
            style: AppTheme.mono(
              size: 10.5,
              color: fg,
              weight: primary ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        );
      },
    );
  }
}

// --- Bodies ------------------------------------------------------------

class _TextBody extends StatelessWidget {
  const _TextBody({
    required this.controller,
    required this.focus,
    required this.multiline,
    required this.onChanged,
    this.inputFormatters,
    this.error,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool multiline;
  final VoidCallback onChanged;
  final List<TextInputFormatter>? inputFormatters;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: CodeEditor(
              controller: controller,
              focusNode: focus,
              singleLine: !multiline,
              fontSize: 12,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              inputFormatters: inputFormatters,
              onChanged: (_) => onChanged(),
            ),
          ),
          if (error != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: const Color(0x33FB7185),
                border: Border(
                  top: BorderSide(color: AppColors.error),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      size: 13, color: AppColors.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.mono(
                        size: 11,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BoolBody extends StatelessWidget {
  const _BoolBody({required this.value, required this.onChange, required this.onNull});

  final bool? value;
  final ValueChanged<bool> onChange;
  final VoidCallback onNull;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          _boolOpt(
            label: 'true',
            icon: Icons.check,
            selected: value == true,
            onTap: () => onChange(true),
          ),
          const SizedBox(width: 4),
          _boolOpt(
            label: 'false',
            icon: Icons.close,
            selected: value == false,
            onTap: () => onChange(false),
          ),
          const SizedBox(width: 4),
          _boolOpt(
            label: 'NULL',
            icon: Icons.horizontal_rule,
            selected: value == null,
            onTap: onNull,
          ),
        ],
      ),
    );
  }
}

Widget _boolOpt({
  required String label,
  required IconData icon,
  required bool selected,
  required VoidCallback onTap,
}) {
  return Expanded(
    child: Hoverable(
      onTap: onTap,
      builder: (_, hover) => Container(
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentSoft
              : (hover ? AppColors.surfaceHover : Colors.transparent),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 10,
              color: selected ? AppColors.textPrimary : AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTheme.mono(
                size: 11,
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// --- Date / time bodies -----------------------------------------------

class _CalendarBody extends StatefulWidget {
  const _CalendarBody({
    required this.initial,
    required this.resetTick,
    required this.onChange,
  });
  final DateTime initial;
  final int resetTick;
  final ValueChanged<DateTime> onChange;

  @override
  State<_CalendarBody> createState() => _CalendarBodyState();
}

class _CalendarBodyState extends State<_CalendarBody> {
  late DateTime _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initial;
  }

  @override
  void didUpdateWidget(_CalendarBody old) {
    super.didUpdateWidget(old);
    if (old.resetTick != widget.resetTick) {
      _current = widget.initial;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: _CalendarThemed(
        key: ValueKey('cal-${widget.resetTick}'),
        initial: _current,
        onChange: (d) {
          setState(() => _current = d);
          widget.onChange(d);
        },
      ),
    );
  }
}

/// Grid-style calendar matching the design handoff — hairlines around every
/// cell, a 3px accent dot under today, and a solid-accent square highlight on
/// the selected day (no pill rounding).
class _CalendarThemed extends StatefulWidget {
  const _CalendarThemed({
    super.key,
    required this.initial,
    required this.onChange,
  });

  final DateTime initial;
  final ValueChanged<DateTime> onChange;

  @override
  State<_CalendarThemed> createState() => _CalendarThemedState();
}

class _CalendarThemedState extends State<_CalendarThemed> {
  late int _vy;
  late int _vm;

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    _vy = widget.initial.year;
    _vm = widget.initial.month;
  }

  @override
  void didUpdateWidget(_CalendarThemed old) {
    super.didUpdateWidget(old);
    if (old.initial != widget.initial) {
      _vy = widget.initial.year;
      _vm = widget.initial.month;
    }
  }

  int _daysInMonth(int y, int m) => DateTime(y, m + 1, 0).day;
  int _firstDow(int y, int m) => DateTime(y, m, 1).weekday % 7;

  void _prev() {
    setState(() {
      if (_vm == 1) {
        _vm = 12;
        _vy -= 1;
      } else {
        _vm -= 1;
      }
    });
  }

  void _next() {
    setState(() {
      if (_vm == 12) {
        _vm = 1;
        _vy += 1;
      } else {
        _vm += 1;
      }
    });
  }

  void _jumpToday() {
    final now = DateTime.now();
    setState(() {
      _vy = now.year;
      _vm = now.month;
    });
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final nDays = _daysInMonth(_vy, _vm);
    final lead = _firstDow(_vy, _vm);
    final trail = 42 - lead - nDays;
    final prevDays = _vm == 1
        ? _daysInMonth(_vy - 1, 12)
        : _daysInMonth(_vy, _vm - 1);

    final cells = <_CalCell>[];
    for (var i = lead - 1; i >= 0; i--) {
      cells.add(_CalCell(day: prevDays - i, outside: true, next: false));
    }
    for (var d = 1; d <= nDays; d++) {
      cells.add(_CalCell(day: d, outside: false, next: false));
    }
    for (var d = 1; d <= trail; d++) {
      cells.add(_CalCell(day: d, outside: true, next: true));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(),
        _dow(),
        _grid(cells, today),
      ],
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          _navBtn(Icons.chevron_left, _prev, 'prev month'),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _months[_vm - 1].toUpperCase(),
                  style: AppTheme.mono(
                    size: 11,
                    color: AppColors.textPrimary,
                    weight: FontWeight.w600,
                  ).copyWith(letterSpacing: 0.04 * 11),
                ),
                const SizedBox(width: 8),
                Text(
                  '$_vy',
                  style: AppTheme.mono(
                    size: 10.5,
                    color: AppColors.textMuted,
                    weight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          _navBtn(Icons.adjust, _jumpToday, 'jump to current month'),
          _navBtn(Icons.chevron_right, _next, 'next month'),
        ],
      ),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback onTap, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: Hoverable(
        onTap: onTap,
        builder: (context, hovering) => Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovering ? AppColors.surfaceHover : Colors.transparent,
            borderRadius: Radii.brSm,
          ),
          child: Icon(
            icon,
            size: icon == Icons.adjust ? 8 : 14,
            color: hovering ? AppColors.textPrimary : AppColors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _dow() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          for (final l in const ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  l,
                  textAlign: TextAlign.center,
                  style: AppTheme.mono(
                    size: 9.5,
                    color: AppColors.text4,
                    weight: FontWeight.w600,
                  ).copyWith(letterSpacing: 0.06 * 9.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _grid(List<_CalCell> cells, DateTime today) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < 6; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(child: _cellWidget(cells[r * 7 + c], today, c)),
            ],
          ),
      ],
    );
  }

  Widget _cellWidget(_CalCell cell, DateTime today, int colIndex) {
    final isToday = !cell.outside &&
        cell.day == today.day &&
        _vm == today.month &&
        _vy == today.year;
    final isSel = !cell.outside &&
        cell.day == widget.initial.day &&
        _vm == widget.initial.month &&
        _vy == widget.initial.year;

    return Hoverable(
      onTap: () {
        final ny = cell.next
            ? (_vm == 12 ? _vy + 1 : _vy)
            : cell.outside
                ? (_vm == 1 ? _vy - 1 : _vy)
                : _vy;
        final nm = cell.next
            ? (_vm == 12 ? 1 : _vm + 1)
            : cell.outside
                ? (_vm == 1 ? 12 : _vm - 1)
                : _vm;
        widget.onChange(DateTime(
          ny,
          nm,
          cell.day,
          widget.initial.hour,
          widget.initial.minute,
          widget.initial.second,
          widget.initial.millisecond,
        ));
        setState(() {
          _vy = ny;
          _vm = nm;
        });
      },
      builder: (context, hovering) {
        final Color bg = isSel
            ? AppColors.accent
            : (hovering && !cell.outside
                ? AppColors.sidebarRowHover
                : Colors.transparent);
        final Color fg = isSel
            ? Colors.white
            : cell.outside
                ? AppColors.text4.withValues(alpha: 0.45)
                : (isToday ? AppColors.textPrimary : AppColors.textSecondary);
        return Container(
          height: 30,
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              right: colIndex == 6
                  ? BorderSide.none
                  : BorderSide(color: AppColors.hairline),
              bottom: BorderSide(color: AppColors.hairline),
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '${cell.day}',
                style: AppTheme.mono(
                  size: 11.5,
                  color: fg,
                  weight: isToday || isSel
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
              if (isToday)
                Positioned(
                  bottom: 4,
                  child: Container(
                    width: 3,
                    height: 3,
                    decoration: BoxDecoration(
                      color: isSel ? Colors.white : AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CalCell {
  const _CalCell({
    required this.day,
    required this.outside,
    required this.next,
  });
  final int day;
  final bool outside;
  final bool next;
}

// ignore: unused_element
class _CalendarThemedLegacy extends StatelessWidget {
  const _CalendarThemedLegacy({
    required this.initial,
    required this.onChange,
  });

  final DateTime initial;
  final ValueChanged<DateTime> onChange;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final cal = DatePickerThemeData(
      backgroundColor: AppColors.bg,
      headerBackgroundColor: AppColors.bg,
      headerForegroundColor: AppColors.textPrimary,
      weekdayStyle: AppTheme.mono(
        size: 10,
        color: AppColors.textMuted,
        weight: FontWeight.w600,
      ),
      dayStyle: AppTheme.mono(size: 11, color: AppColors.textSecondary),
      yearStyle: AppTheme.mono(size: 12, color: AppColors.textSecondary),
      dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.accent;
        return null;
      }),
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.bg;
        if (states.contains(WidgetState.disabled)) return AppColors.textMuted;
        return AppColors.textPrimary;
      }),
      dayOverlayColor: WidgetStateProperty.all(
        AppColors.accent.withValues(alpha: 0.12),
      ),
      dayShape: WidgetStateProperty.all(
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
      ),
      todayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.accent;
        return Colors.transparent;
      }),
      todayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.bg;
        return AppColors.accent;
      }),
      todayBorder: BorderSide(color: AppColors.accent, width: 1),
      yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.accent;
        return null;
      }),
      yearForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.bg;
        return AppColors.textPrimary;
      }),
      yearOverlayColor: WidgetStateProperty.all(
        AppColors.accent.withValues(alpha: 0.12),
      ),
      dividerColor: AppColors.border,
    );

    return Theme(
      data: base.copyWith(
        datePickerTheme: cal,
        textTheme: base.textTheme.apply(
          fontFamily: AppTheme.mono().fontFamily,
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        ),
        colorScheme: base.colorScheme.copyWith(
          primary: AppColors.accent,
          onPrimary: AppColors.bg,
          surface: AppColors.bg,
          onSurface: AppColors.textPrimary,
        ),
        iconTheme: IconThemeData(
          color: AppColors.textSecondary,
          size: 16,
        ),
      ),
      child: CalendarDatePicker(
        initialDate: initial,
        firstDate: DateTime(1900),
        lastDate: DateTime(2200),
        onDateChanged: onChange,
      ),
    );
  }
}

class _TimeBody extends StatelessWidget {
  const _TimeBody({
    required this.initial,
    required this.withTz,
    required this.tz,
    required this.resetTick,
    required this.onChange,
    required this.onTzChange,
  });

  final DateTime initial;
  final bool withTz;
  final String tz;
  final int resetTick;
  final void Function(int hour, int minute, int second, int ms) onChange;
  final ValueChanged<String> onTzChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TimeInput(
            key: ValueKey('time-$resetTick'),
            initial: initial,
            onChange: onChange,
          ),
          if (withTz) ...[
            const SizedBox(height: 10),
            _TzInput(value: tz, onChange: onTzChange),
          ],
        ],
      ),
    );
  }
}

class _DateTimeBody extends StatefulWidget {
  const _DateTimeBody({
    required this.initial,
    required this.withTz,
    required this.tz,
    required this.resetTick,
    required this.onChange,
    required this.onTzChange,
  });

  final DateTime initial;
  final bool withTz;
  final String tz;
  final int resetTick;
  final ValueChanged<DateTime> onChange;
  final ValueChanged<String> onTzChange;

  @override
  State<_DateTimeBody> createState() => _DateTimeBodyState();
}

class _DateTimeBodyState extends State<_DateTimeBody> {
  late DateTime _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
  }

  @override
  void didUpdateWidget(_DateTimeBody old) {
    super.didUpdateWidget(old);
    if (old.resetTick != widget.resetTick) {
      _value = widget.initial;
    }
  }

  void _setDate(DateTime d) {
    final next = DateTime(
      d.year,
      d.month,
      d.day,
      _value.hour,
      _value.minute,
      _value.second,
      _value.millisecond,
    );
    setState(() => _value = next);
    widget.onChange(next);
  }

  @override
  Widget build(BuildContext context) {
    // The hours/minutes/seconds are edited via the arrow-key segments in the
    // `_MonoValueLine` above the body, so the body itself only carries the
    // calendar (plus an optional TZ input — kept here because the value line
    // surfaces TZ as a small chip rather than an editable text field).
    return Container(
      color: AppColors.bg,
      child: Column(
        children: [
          Expanded(
            child: _CalendarThemed(
              key: ValueKey('cal-${widget.resetTick}'),
              initial: _value,
              onChange: _setDate,
            ),
          ),
          if (widget.withTz) ...[
            Divider(height: 1, color: AppColors.border),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child:
                  _TzInput(value: widget.tz, onChange: widget.onTzChange),
            ),
          ],
        ],
      ),
    );
  }
}

/// Four small numeric fields HH : MM : SS . MS, value flows out via [onChange].
class _TimeInput extends StatefulWidget {
  const _TimeInput({
    super.key,
    required this.initial,
    required this.onChange,
  });
  final DateTime initial;
  final void Function(int hour, int minute, int second, int ms) onChange;

  @override
  State<_TimeInput> createState() => _TimeInputState();
}

class _TimeInputState extends State<_TimeInput> {
  late final TextEditingController _h;
  late final TextEditingController _m;
  late final TextEditingController _s;
  late final TextEditingController _ms;

  @override
  void initState() {
    super.initState();
    _h = TextEditingController(text: _pad(widget.initial.hour));
    _m = TextEditingController(text: _pad(widget.initial.minute));
    _s = TextEditingController(text: _pad(widget.initial.second));
    _ms = TextEditingController(text: _pad3(widget.initial.millisecond));
  }

  @override
  void dispose() {
    _h.dispose();
    _m.dispose();
    _s.dispose();
    _ms.dispose();
    super.dispose();
  }

  void _emit() {
    final h = (int.tryParse(_h.text) ?? 0).clamp(0, 23);
    final m = (int.tryParse(_m.text) ?? 0).clamp(0, 59);
    final s = (int.tryParse(_s.text) ?? 0).clamp(0, 59);
    final ms = (int.tryParse(_ms.text) ?? 0).clamp(0, 999);
    widget.onChange(h, m, s, ms);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _segment(_h, 'HH', width: 40, maxLen: 2),
        _sep(':'),
        _segment(_m, 'MM', width: 40, maxLen: 2),
        _sep(':'),
        _segment(_s, 'SS', width: 40, maxLen: 2),
        _sep('.'),
        _segment(_ms, 'MS', width: 50, maxLen: 3),
      ],
    );
  }

  Widget _segment(
    TextEditingController c,
    String hint, {
    required double width,
    required int maxLen,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: c,
        textAlign: TextAlign.center,
        cursorColor: AppColors.accent,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(maxLen),
        ],
        onChanged: (_) => _emit(),
        onSubmitted: (_) => _emit(),
        style: AppTheme.mono(size: 15, weight: FontWeight.w600),
        decoration: InputDecoration(
          isCollapsed: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
          hintText: hint,
          hintStyle: AppTheme.mono(size: 12, color: AppColors.textMuted),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: Radii.brSm,
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: Radii.brSm,
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: Radii.brSm,
            borderSide: BorderSide(color: AppColors.accent),
          ),
        ),
      ),
    );
  }

  Widget _sep(String c) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          c,
          style: AppTheme.mono(size: 15, color: AppColors.textMuted),
        ),
      );
}

/// Timezone text input — accepts free-form `UTC`, `+02:00`, `Europe/Berlin`, …
class _TzInput extends StatefulWidget {
  const _TzInput({required this.value, required this.onChange});
  final String value;
  final ValueChanged<String> onChange;

  @override
  State<_TzInput> createState() => _TzInputState();
}

class _TzInputState extends State<_TzInput> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_TzInput old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _c.text != widget.value) {
      _c.text = widget.value;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: Radii.brSm,
          ),
          child: Text(
            'TZ',
            style: AppTheme.mono(
              size: 10,
              color: AppColors.textMuted,
              weight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: _c,
            cursorColor: AppColors.accent,
            onChanged: widget.onChange,
            style: AppTheme.mono(size: 12),
            decoration: InputDecoration(
              isCollapsed: true,
              hintText: 'UTC / +02:00 / Europe/Berlin',
              hintStyle:
                  AppTheme.mono(size: 11.5, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              border: OutlineInputBorder(
                borderRadius: Radii.brSm,
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: Radii.brSm,
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: Radii.brSm,
                borderSide: BorderSide(color: AppColors.accent),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Mono value line shown above date / time / datetime pickers — the design's
/// `.dt-valueline`, one tabular row showing the chosen moment in
/// `yyyy-mm-dd hh:mm:ss[@tz]` form with arrow-key bump on focused segments.
class _MonoValueLine extends StatelessWidget {
  const _MonoValueLine({
    required this.kind,
    required this.moment,
    required this.tz,
    required this.withTz,
    required this.onChange,
    required this.onTzChange,
  });

  final _KindId kind;
  final DateTime moment;
  final String tz;
  final bool withTz;
  final ValueChanged<DateTime> onChange;
  final ValueChanged<String> onTzChange;

  int _daysInMonth(int y, int m) => DateTime(y, m + 1, 0).day;

  void _setYear(int v) {
    onChange(DateTime(v, moment.month, moment.day, moment.hour,
        moment.minute, moment.second, moment.millisecond));
  }

  void _setMonth(int v) {
    final clampedDay = moment.day.clamp(1, _daysInMonth(moment.year, v));
    onChange(DateTime(moment.year, v, clampedDay, moment.hour,
        moment.minute, moment.second, moment.millisecond));
  }

  void _setDay(int v) {
    final clampedDay = v.clamp(1, _daysInMonth(moment.year, moment.month));
    onChange(DateTime(moment.year, moment.month, clampedDay, moment.hour,
        moment.minute, moment.second, moment.millisecond));
  }

  void _setHour(int v) {
    onChange(DateTime(moment.year, moment.month, moment.day, v,
        moment.minute, moment.second, moment.millisecond));
  }

  void _setMinute(int v) {
    onChange(DateTime(moment.year, moment.month, moment.day, moment.hour, v,
        moment.second, moment.millisecond));
  }

  void _setSecond(int v) {
    onChange(DateTime(moment.year, moment.month, moment.day, moment.hour,
        moment.minute, v, moment.millisecond));
  }

  @override
  Widget build(BuildContext context) {
    final hasDate = kind == _KindId.date || kind == _KindId.datetime;
    final hasTime = kind == _KindId.time || kind == _KindId.datetime;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          if (hasDate) ...[
            _Seg(
              value: moment.year,
              width: 44,
              padTo: 4,
              minValue: 1,
              maxValue: 9999,
              onChanged: _setYear,
            ),
            const _Punct('-'),
            _Seg(
              value: moment.month,
              width: 26,
              padTo: 2,
              minValue: 1,
              maxValue: 12,
              onChanged: _setMonth,
            ),
            const _Punct('-'),
            _Seg(
              value: moment.day,
              width: 26,
              padTo: 2,
              minValue: 1,
              maxValue: 31,
              onChanged: _setDay,
            ),
          ],
          if (hasDate && hasTime) const SizedBox(width: 12),
          if (hasTime) ...[
            _Seg(
              value: moment.hour,
              width: 26,
              padTo: 2,
              minValue: 0,
              maxValue: 23,
              onChanged: _setHour,
            ),
            const _Punct(':'),
            _Seg(
              value: moment.minute,
              width: 26,
              padTo: 2,
              minValue: 0,
              maxValue: 59,
              onChanged: _setMinute,
            ),
            const _Punct(':'),
            _Seg(
              value: moment.second,
              width: 26,
              padTo: 2,
              minValue: 0,
              maxValue: 59,
              onChanged: _setSecond,
            ),
          ],
          if (withTz && hasTime) ...[
            const _AtPunct(),
            _TzChip(value: tz, onChange: onTzChange),
          ],
        ],
      ),
    );
  }
}

/// A single digit field inside the mono value line — click to focus and type
/// (or paste) the new value. On blur or `Enter`, the entered number is
/// clamped to [[minValue], [maxValue]], re-padded to [padTo] digits, and
/// pushed back through [onChanged] so the parent's [DateTime] reconstruction
/// runs once with a known-good value.
class _Seg extends StatefulWidget {
  const _Seg({
    required this.value,
    required this.width,
    required this.padTo,
    required this.minValue,
    required this.maxValue,
    required this.onChanged,
  });

  final int value;
  final double width;
  final int padTo;
  final int minValue;
  final int maxValue;
  final ValueChanged<int> onChanged;

  @override
  State<_Seg> createState() => _SegState();
}

class _SegState extends State<_Seg> {
  late final TextEditingController _c;
  late final FocusNode _focus;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: _formatted(widget.value));
    _focus = FocusNode();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_Seg old) {
    super.didUpdateWidget(old);
    if (!_editing && old.value != widget.value) {
      _c.text = _formatted(widget.value);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _c.dispose();
    super.dispose();
  }

  String _formatted(int n) => n.toString().padLeft(widget.padTo, '0');

  void _onFocusChange() {
    if (!_focus.hasFocus && _editing) {
      _commit();
      setState(() => _editing = false);
    }
  }

  void _startEditing() {
    if (_editing) return;
    _c.text = _formatted(widget.value);
    setState(() => _editing = true);
    // The TextField is built next frame — request focus after it's mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      _c.selection =
          TextSelection(baseOffset: 0, extentOffset: _c.text.length);
    });
  }

  void _commit() {
    final raw = _c.text.trim();
    final parsed = int.tryParse(raw) ?? widget.value;
    final clamped = parsed.clamp(widget.minValue, widget.maxValue);
    if (clamped != widget.value) widget.onChanged(clamped);
    final padded = _formatted(clamped);
    if (_c.text != padded) _c.text = padded;
  }

  @override
  Widget build(BuildContext context) {
    // The mono value line is dense and the read-only path needs to be
    // pixel-perfect; rendering a TextField full-time fights Material's
    // internal layout (cursor reservation, scroll padding) and clips at
    // tight widths. Default to a plain Text and only swap to a TextField
    // while the user is actually editing.
    if (_editing) return _editor();
    return _readonly();
  }

  Widget _readonly() {
    return Hoverable(
      cursor: SystemMouseCursors.text,
      onTap: _startEditing,
      builder: (context, hovering) => Container(
        width: widget.width,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              hovering ? AppColors.surfaceHover : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          _formatted(widget.value),
          style: AppTheme.mono(
            size: 14,
            color: AppColors.textPrimary,
            weight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _editor() {
    return Container(
      width: widget.width,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(3),
      ),
      child: EditableText(
        controller: _c,
        focusNode: _focus,
        autofocus: true,
        textAlign: TextAlign.center,
        cursorColor: AppColors.accent,
        backgroundCursorColor: AppColors.accent,
        keyboardType: TextInputType.number,
        scrollPhysics: const NeverScrollableScrollPhysics(),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(widget.padTo),
        ],
        onSubmitted: (_) {
          _commit();
          _focus.unfocus();
        },
        style: AppTheme.mono(
          size: 14,
          color: AppColors.textPrimary,
          weight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _Punct extends StatelessWidget {
  const _Punct(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Text(
        text,
        style: AppTheme.mono(
          size: 14,
          color: AppColors.text4,
        ),
      ),
    );
  }
}

class _AtPunct extends StatelessWidget {
  const _AtPunct();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 6),
      child: Text(
        '@',
        style: AppTheme.mono(size: 14, color: AppColors.text4),
      ),
    );
  }
}

class _TzChip extends StatelessWidget {
  const _TzChip({required this.value, required this.onChange});
  final String value;
  final ValueChanged<String> onChange;

  static const _options = [
    ('-08', 'PST'),
    ('-07', 'PDT/MST'),
    ('-05', 'EST'),
    ('+00', 'UTC'),
    ('+01', 'CET'),
    ('+05:30', 'IST'),
    ('+09', 'JST'),
  ];

  void _show(BuildContext context, RenderBox anchor) {
    final overlay = Overlay.of(context);
    final origin = anchor.localToGlobal(Offset(0, anchor.size.height + 4));
    late OverlayEntry entry;
    void close() {
      if (entry.mounted) entry.remove();
    }

    entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: close,
            ),
          ),
          Positioned(
            left: origin.dx,
            top: origin.dy,
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(minWidth: 110),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: Radii.brSm,
                  border: Border.all(color: AppColors.borderStrong),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x88000000),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (tz, lbl) in _options)
                      Hoverable(
                        onTap: () {
                          close();
                          onChange(tz);
                        },
                        builder: (context, hovering) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: hovering
                                ? AppColors.surfaceHover
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Row(
                            children: [
                              Text(
                                tz,
                                style: AppTheme.mono(
                                  size: 11,
                                  color: tz == value
                                      ? AppColors.accent
                                      : AppColors.textSecondary,
                                  weight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                lbl,
                                style: AppTheme.mono(
                                  size: 10,
                                  color: AppColors.text4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    final display = value.trim().isEmpty ? '+00' : value;
    return Builder(
      builder: (context) {
        return Hoverable(
          cursor: SystemMouseCursors.click,
          onTap: () {
            final box = context.findRenderObject() as RenderBox?;
            if (box != null) _show(context, box);
          },
          builder: (context, hovering) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: hovering ? AppColors.accentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  display,
                  style: AppTheme.mono(
                    size: 14,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  Icons.expand_more,
                  size: 10,
                  color: AppColors.text4,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Row of 3 quick actions (Now / Today / shift) under the value line. The
/// `primary` action lights in the accent, others stay quiet.
class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({required this.children});
  final List<_QuickAction> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            Expanded(child: children[i]),
            if (i < children.length - 1)
              Container(
                width: 1,
                height: 28,
                color: AppColors.hairline,
              ),
          ],
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.label,
    required this.onTap,
    this.icon,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final Color fg = primary ? AppColors.accent : AppColors.textSecondary;
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) {
        final Color bg = primary && hovering
            ? AppColors.accentSoft
            : (hovering ? AppColors.sidebarRowHover : Colors.transparent);
        final Color fgHover =
            hovering && !primary ? AppColors.textPrimary : fg;
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          alignment: Alignment.center,
          color: bg,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 10, color: fgHover),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: AppTheme.mono(
                  size: 11.5,
                  color: fgHover,
                  weight: primary ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


/// Right-aligned mono input + vertical stepper for the number kind.
/// Matches the design's `.num-field` / `.num-steppers` layout.
class _NumberBody extends StatefulWidget {
  const _NumberBody({
    required this.controller,
    required this.focus,
    required this.intOnly,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool intOnly;
  final VoidCallback onChanged;

  @override
  State<_NumberBody> createState() => _NumberBodyState();
}

class _NumberBodyState extends State<_NumberBody> {
  void _bump(int delta) {
    final raw = widget.controller.text.trim();
    final current =
        num.tryParse(raw.isEmpty ? '0' : raw) ?? num.parse('0');
    final next =
        widget.intOnly ? (current + delta).round() : current + delta;
    widget.controller.text = next.toString();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgDeep,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: AppColors.border),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focus,
                  textAlign: TextAlign.right,
                  cursorColor: AppColors.accent,
                  inputFormatters: [
                    widget.intOnly ? _intFilter : _numberFilter,
                  ],
                  style: AppTheme.mono(
                    size: 12,
                    color: AppColors.textPrimary,
                  ).copyWith(
                    fontFeatures: const [
                      FontFeature.tabularFigures(),
                    ],
                  ),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
              Container(
                width: 1,
                color: AppColors.border,
              ),
              Column(
                children: [
                  _StepperBtn(
                    icon: Icons.keyboard_arrow_up,
                    onTap: () => _bump(1),
                  ),
                  Container(width: 22, height: 1, color: AppColors.border),
                  _StepperBtn(
                    icon: Icons.keyboard_arrow_down,
                    onTap: () => _bump(-1),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepperBtn extends StatelessWidget {
  const _StepperBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => Container(
        width: 22,
        height: 18,
        alignment: Alignment.center,
        color: hovering ? AppColors.surfaceHover : Colors.transparent,
        child: Icon(
          icon,
          size: 14,
          color: hovering ? AppColors.textPrimary : AppColors.textMuted,
        ),
      ),
    );
  }
}
