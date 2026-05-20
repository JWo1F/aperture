import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:postgres/postgres.dart';

import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/json_highlight_controller.dart';

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
  required dynamic originalValue,
  required CellEditValue? pendingEdit,
  required ValueChanged<CellEditValue> onCommit,
  VoidCallback? onRevert,
  bool canBeNull = true,
  bool hasDefault = false,
  String? columnDataType,
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

const _kBool = _Kind(
  id: _KindId.bool,
  label: 'bool',
  color: AppColors.sqlFunction,
  size: Size(240, 130),
);
const _kJson = _Kind(
  id: _KindId.json,
  label: 'json',
  color: AppColors.sqlString,
  size: Size(540, 340),
  multiline: true,
);
const _kArray = _Kind(
  id: _KindId.json,
  label: 'array',
  color: AppColors.sqlString,
  size: Size(540, 340),
  multiline: true,
);
final _kInt = _Kind(
  id: _KindId.text,
  label: 'int',
  color: AppColors.sqlNumber,
  size: const Size(260, 132),
  inputFormatters: [_intFilter],
);
final _kNumber = _Kind(
  id: _KindId.text,
  label: 'number',
  color: AppColors.sqlNumber,
  size: const Size(260, 132),
  inputFormatters: [_numberFilter],
);
const _kDate = _Kind(
  id: _KindId.date,
  label: 'date',
  color: AppColors.info,
  size: Size(252, 296),
);
const _kTime = _Kind(
  id: _KindId.time,
  label: 'time',
  color: AppColors.info,
  size: Size(252, 126),
);
const _kTimeTz = _Kind(
  id: _KindId.time,
  label: 'timetz',
  color: AppColors.info,
  size: Size(252, 168),
  withTimezone: true,
);
const _kDatetime = _Kind(
  id: _KindId.datetime,
  label: 'timestamp',
  color: AppColors.info,
  size: Size(252, 360),
);
const _kDatetimeTz = _Kind(
  id: _KindId.datetime,
  label: 'timestamptz',
  color: AppColors.info,
  size: Size(252, 400),
  withTimezone: true,
);
const _kBytes = _Kind(
  id: _KindId.text,
  label: 'bytes',
  color: AppColors.textMuted,
  size: Size(380, 220),
  multiline: true,
);
const _kString = _Kind(
  id: _KindId.text,
  label: 'string',
  color: AppColors.textSecondary,
  size: Size(380, 220),
  multiline: true,
);

/// Picks a picker shape. The column's `dataType` (from the catalog) is the
/// authoritative source — falls back to the runtime value's class when the
/// caller doesn't have catalog metadata yet.
_Kind _kindFor(dynamic v, String? dataType) {
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
  if (v is UndecodedBytes) return _kBytes;
  return _kString;
}

// --- Initial state extraction -----------------------------------------

String _initialText(dynamic raw, CellEditValue? pending) {
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
  if (raw is UndecodedBytes) return raw.isBinary ? '' : raw.asString;
  if (raw is DateTime) return raw.toIso8601String();
  return raw.toString();
}

bool? _initialBool(dynamic raw, CellEditValue? pending) {
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

DateTime _initialMoment(dynamic raw, CellEditValue? pending) {
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
String _initialTz(dynamic raw, CellEditValue? pending) {
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
    required this.onCommit,
    required this.onRevert,
    required this.onClose,
  });

  final _Kind kind;
  final Rect anchorRect;
  final String columnName;
  final dynamic originalValue;
  final CellEditValue? pendingEdit;
  final bool canBeNull;
  final bool hasDefault;
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
    required this.onCommit,
    required this.onRevert,
    required this.onClose,
  });

  final _Kind kind;
  final String columnName;
  final dynamic originalValue;
  final CellEditValue? pendingEdit;
  final bool canBeNull;
  final bool hasDefault;
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
            ? JsonHighlightController(text: _baselineText)
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
            borderRadius: Radii.brMd,
            border: Border.all(color: AppColors.borderStrong),
            boxShadow: const [
              BoxShadow(
                color: Color(0xAA000000),
                blurRadius: 30,
                offset: Offset(0, 12),
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
                onClose: widget.onClose,
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(child: _buildBody()),
              const Divider(height: 1, color: AppColors.border),
              _Footer(
                hasPending: widget.pendingEdit != null,
                canSave: _isDirty,
                canBeNull: widget.canBeNull,
                hasDefault: widget.hasDefault,
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

  Widget _buildBody() {
    switch (widget.kind.id) {
      case _KindId.bool:
        return _BoolBody(
          value: _bool,
          onChange: (v) => setState(() => _bool = v),
        );
      case _KindId.date:
        return _CalendarBody(
          initial: _moment!,
          onChange: (d) => setState(() {
            _moment = DateTime(d.year, d.month, d.day);
          }),
        );
      case _KindId.time:
        return _TimeBody(
          initial: _moment!,
          withTz: widget.kind.withTimezone,
          tz: _tz,
          onChange: (h, m, s, ms) => setState(() {
            _moment = DateTime(1970, 1, 1, h, m, s, ms);
          }),
          onTzChange: (tz) => setState(() => _tz = tz),
        );
      case _KindId.datetime:
        return _DateTimeBody(
          initial: _moment!,
          withTz: widget.kind.withTimezone,
          tz: _tz,
          onChange: (dt) => setState(() => _moment = dt),
          onTzChange: (tz) => setState(() => _tz = tz),
        );
      case _KindId.text:
      case _KindId.json:
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
    required this.onClose,
  });

  final String columnName;
  final _Kind kind;
  final CellEditValue? pendingEdit;
  final VoidCallback onClose;

  String? _pendingLabel() => switch (pendingEdit) {
        CellLiteral(:final value) when value == null => 'NULL',
        CellLiteral() => 'edited',
        CellDefault() => 'DEFAULT',
        null => null,
      };

  @override
  Widget build(BuildContext context) {
    final pending = _pendingLabel();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: kind.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              columnName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.mono(size: 11.5, weight: FontWeight.w600),
            ),
          ),
          _Tag(label: kind.label, color: kind.color),
          if (pending != null) ...[
            const SizedBox(width: 4),
            _Tag(label: pending, color: AppColors.accent),
          ],
          GestureDetector(
            onTap: onClose,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close, size: 13, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: Radii.brSm,
      ),
      child: Text(
        label,
        style:
            AppTheme.mono(size: 9.5, color: color, weight: FontWeight.w700),
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
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final VoidCallback onSetNull;
  final VoidCallback onSetDefault;
  final VoidCallback? onRevert;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(
        children: [
          if (hasPending) ...[
            IconAction(
              icon: Icons.undo,
              tooltip: 'Revert',
              onPressed: onRevert,
            ),
            const SizedBox(width: 2),
          ],
          IconAction(
            icon: Icons.not_interested,
            tooltip: canBeNull ? 'Set NULL' : 'Column is NOT NULL',
            onPressed: canBeNull ? onSetNull : null,
          ),
          const SizedBox(width: 2),
          IconAction(
            icon: Icons.settings_backup_restore,
            tooltip: hasDefault ? 'Set DEFAULT' : 'Column has no default',
            onPressed: hasDefault ? onSetDefault : null,
          ),
          const Spacer(),
          GestureDetector(
            onTap: onCancel,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                'Cancel',
                style: AppTheme.ui(
                  size: 12,
                  color: AppColors.textSecondary,
                  weight: FontWeight.w500,
                ),
              ),
            ),
          ),
          IconAction(
            icon: Icons.check,
            tooltip: 'Save (⌘↵)',
            primary: true,
            onPressed: canSave ? onSave : null,
          ),
        ],
      ),
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
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: TextField(
                controller: controller,
                focusNode: focus,
                maxLines: multiline ? null : 1,
                expands: multiline,
                textAlignVertical: TextAlignVertical.top,
                cursorColor: AppColors.accent,
                onChanged: (_) => onChanged(),
                inputFormatters: inputFormatters,
                style:
                    AppTheme.mono(size: 12, color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          if (error != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 7,
              ),
              decoration: const BoxDecoration(
                color: Color(0x33FB7185),
                border: Border(
                  top: BorderSide(color: AppColors.error),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
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
  const _BoolBody({required this.value, required this.onChange});

  final bool? value;
  final ValueChanged<bool> onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: _BoolChoice(
              label: 'true',
              selected: value == true,
              onTap: () => onChange(true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _BoolChoice(
              label: 'false',
              selected: value == false,
              onTap: () => onChange(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoolChoice extends StatefulWidget {
  const _BoolChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_BoolChoice> createState() => _BoolChoiceState();
}

class _BoolChoiceState extends State<_BoolChoice> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accentSoft
                : (_hover ? AppColors.surfaceHover : AppColors.surface),
            borderRadius: Radii.brMd,
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Text(
            widget.label,
            style: AppTheme.mono(
              size: 13,
              color: selected ? AppColors.accent : AppColors.textSecondary,
              weight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// --- Date / time bodies -----------------------------------------------

class _CalendarBody extends StatefulWidget {
  const _CalendarBody({required this.initial, required this.onChange});
  final DateTime initial;
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
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: _CalendarThemed(
        initial: _current,
        onChange: (d) {
          setState(() => _current = d);
          widget.onChange(d);
        },
      ),
    );
  }
}

/// CalendarDatePicker wrapped in a tight Material 3 theme override so the
/// selected / today states fit the Aperture palette and the smaller frame.
class _CalendarThemed extends StatelessWidget {
  const _CalendarThemed({required this.initial, required this.onChange});

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
      todayBorder: const BorderSide(color: AppColors.accent, width: 1),
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
        iconTheme: const IconThemeData(
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
    required this.onChange,
    required this.onTzChange,
  });

  final DateTime initial;
  final bool withTz;
  final String tz;
  final void Function(int hour, int minute, int second, int ms) onChange;
  final ValueChanged<String> onTzChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        children: [
          _TimeInput(initial: initial, onChange: onChange),
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
    required this.onChange,
    required this.onTzChange,
  });

  final DateTime initial;
  final bool withTz;
  final String tz;
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

  void _setTime(int h, int m, int s, int ms) {
    final next = DateTime(
      _value.year,
      _value.month,
      _value.day,
      h,
      m,
      s,
      ms,
    );
    setState(() => _value = next);
    widget.onChange(next);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: Column(
        children: [
          Expanded(
            child: _CalendarThemed(
              initial: _value,
              onChange: _setDate,
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              children: [
                _TimeInput(initial: _value, onChange: _setTime),
                if (widget.withTz) ...[
                  const SizedBox(height: 8),
                  _TzInput(value: widget.tz, onChange: widget.onTzChange),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Four small numeric fields HH : MM : SS . MS, value flows out via [onChange].
class _TimeInput extends StatefulWidget {
  const _TimeInput({required this.initial, required this.onChange});
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
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: Radii.brSm,
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: Radii.brSm,
            borderSide: const BorderSide(color: AppColors.accent),
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
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: Radii.brSm,
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: Radii.brSm,
                borderSide: const BorderSide(color: AppColors.accent),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
