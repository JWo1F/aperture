import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import 'bodies/bool_body.dart';
import 'bodies/calendar_body.dart';
import 'bodies/datetime_body.dart';
import 'bodies/number_body.dart';
import 'bodies/text_body.dart';
import 'chrome.dart';
import 'editor_state.dart';
import 'formatters.dart';
import 'kinds.dart';
import 'quick_actions.dart';
import 'target.dart';
import 'value_line.dart';
import '../../theme/hugeicons.dart';
import '../widgets/command_key.dart';

// Top-level so the isolate closure captures only the value; one built in a
// State method would carry the State, its timers and the widget tree.
Future<String> _seedTextOnIsolate(
  Object? raw,
  CellEditValue? pending, {
  required bool isJson,
}) => Isolate.run(
  () => isJson ? initialText(raw, pending) : initialArrayText(raw, pending),
);

/// The picker's core widget: hosts the kind-specific [EditorState], dispatches
/// `save` / `revert` / `setNull` / `setDefault`, and assembles the per-kind
/// body between the header and footer.
class Panel extends StatefulWidget {
  const Panel({
    super.key,
    required this.kind,
    required this.target,
    required this.onCommit,
    required this.onRevert,
    required this.onClose,
  });

  final Kind kind;
  final CellEditTarget target;
  final ValueChanged<CellEditValue> onCommit;
  final VoidCallback? onRevert;
  final VoidCallback onClose;

  @override
  State<Panel> createState() => _PanelState();
}

class _PanelState extends State<Panel> {
  // Unset until [_ready]: JSON and array values are serialised (and JSON
  // highlighted) on a background isolate, and the panel shows a spinner
  // instead of freezing the window on a large document.
  late EditorState _state;
  bool _ready = false;
  bool _showSpinner = false;
  Object? _prepareError;
  Timer? _spinnerDelay;

  // Bumped whenever Now/Today resets the moment; passed as a Key to the
  // time/calendar sub-widgets so they refresh their internal state without
  // losing the cursor during normal user typing.
  int _resetTick = 0;

  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    final k = widget.kind.id;
    switch (k) {
      case KindId.bool:
        final v = initialBool(
          widget.target.originalValue,
          widget.target.pendingEdit,
        );
        _state = BoolEditorState(value: v, baseline: v);
        _ready = true;
      case KindId.date:
      case KindId.time:
      case KindId.datetime:
        final m = initialMoment(
          widget.target.originalValue,
          widget.target.pendingEdit,
        );
        final withTz = widget.kind.withTimezone;
        final tz = withTz
            ? initialTz(widget.target.originalValue, widget.target.pendingEdit)
            : '';
        _state = MomentEditorState(
          value: m,
          baselineValue: m,
          tz: tz,
          baselineTz: tz,
          withTz: withTz,
        );
        _ready = true;
      case KindId.text:
        final text = initialText(
          widget.target.originalValue,
          widget.target.pendingEdit,
        );
        _state = _isNumber
            ? NumberEditorState(
                controller: TextEditingController(text: text),
                baseline: text,
              )
            : TextEditorState(
                controller: CodeLineEditingController.fromText(text),
                baseline: text,
                isJson: false,
              );
        _ready = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focus.requestFocus();
        });
      case KindId.json:
      case KindId.array:
        // A spinner that flashes for one frame on a small value reads as a
        // glitch; show it only once the work is visibly taking time.
        _spinnerDelay = Timer(const Duration(milliseconds: 120), () {
          if (mounted && !_ready) setState(() => _showSpinner = true);
        });
        _prepareStructured(k);
    }
  }

  Future<void> _prepareStructured(KindId k) async {
    final raw = widget.target.originalValue;
    final pending = widget.target.pendingEdit;
    final isJson = k == KindId.json;
    try {
      // An array seeds as a Postgres array literal, not as JSON. The grid
      // paints `[1,2]` because that reads better in a cell, but that is not
      // a value the column accepts back — `SET tags = '[1,2]'` is a
      // malformed array literal. Seeding the braces form means what the
      // user sees is what gets written.
      final text = await _seedTextOnIsolate(raw, pending, isJson: isJson);
      if (!mounted) return;
      _spinnerDelay?.cancel();
      setState(() {
        _state = TextEditorState(
          controller: CodeLineEditingController.fromText(text),
          baseline: text,
          isJson: isJson,
        );
        _ready = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    } catch (e) {
      _spinnerDelay?.cancel();
      if (mounted) setState(() => _prepareError = e);
    }
  }

  @override
  void dispose() {
    _spinnerDelay?.cancel();
    if (_ready) _state.disposeResources();
    _focus.dispose();
    super.dispose();
  }

  bool get _isNumber =>
      widget.kind.label == 'number' || widget.kind.label == 'int';

  bool get _isDirty => _ready && _state.isDirty;

  void _save() {
    if (!_ready) return;
    switch (_state) {
      case BoolEditorState s:
        if (s.value == null) return;
        widget.onCommit(CellLiteral(s.value! ? 'true' : 'false'));
      case MomentEditorState s:
        final tz = s.withTz ? s.tz : null;
        final literal = switch (widget.kind.id) {
          KindId.date => formatDate(s.value),
          KindId.time => formatTime(s.value, tz: tz),
          KindId.datetime => formatDateTime(s.value, tz: tz),
          _ => null,
        };
        if (literal != null) widget.onCommit(CellLiteral(literal));
      case TextEditorState s when s.isJson:
        // Validate before committing — empty input is allowed (and means
        // "send the empty string", e.g. for an empty jsonb column).
        final text = s.controller.text;
        if (text.trim().isNotEmpty) {
          try {
            jsonDecode(text);
          } catch (e) {
            setState(() => s.jsonError = _shortJsonError(e));
            return;
          }
        }
        setState(() => s.jsonError = null);
        widget.onCommit(CellLiteral(text));
      case TextEditorState s:
        widget.onCommit(CellLiteral(s.controller.text));
      case NumberEditorState s:
        widget.onCommit(CellLiteral(s.controller.text));
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

  MomentEditorState get _moment => _state as MomentEditorState;

  /// Mutates the moment through [f] and bumps [_resetTick] so child widgets
  /// with internal controllers (calendar, time spinner) rebuild from scratch.
  void _applyMoment(DateTime Function(DateTime) f) {
    setState(() {
      _moment.value = f(_moment.value);
      _resetTick++;
    });
  }

  void _setToNow() {
    setState(() {
      _moment.value = DateTime.now();
      if (_moment.withTz) _moment.tz = '';
      _resetTick++;
    });
  }

  void _shiftDate({int days = 0}) =>
      _applyMoment((m) => m.add(Duration(days: days)));

  void _shiftHour({int hours = 0}) =>
      _applyMoment((m) => m.add(Duration(hours: hours)));

  void _roundHour() =>
      _applyMoment((m) => m.copyWith(minute: 0, second: 0, millisecond: 0));

  void _setToday({bool zeroTime = false}) => _applyMoment((m) {
    final n = DateTime.now();
    return zeroTime
        ? DateTime(n.year, n.month, n.day)
        : m.copyWith(year: n.year, month: n.month, day: n.day);
  });

  @override
  Widget build(BuildContext context) {
    // The picker lives in an OverlayEntry, outside the grid's element
    // tree, so `CallbackShortcuts` only sees keys if focus is inside it.
    // Only the text and JSON kinds request focus for their field; the
    // bool, date and time bodies never did, so the footer advertised
    // `⌘↵ commit · esc cancel` while Escape fell through to the grid and
    // silently cleared the cell selection behind the open picker. This
    // FocusScope gives every kind somewhere for focus to land.
    return FocusScope(
      autofocus: true,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
          commandActivator(LogicalKeyboardKey.enter): _save,
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: Radii.brMd,
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Header(target: widget.target, kind: widget.kind),
                Expanded(child: _buildBody()),
                Footer(
                  canSave: _isDirty,
                  showNull:
                      widget.target.canBeNull && widget.kind.id != KindId.bool,
                  showDefault: widget.target.hasDefault,
                  onSave: _save,
                  onSetNull: _setNull,
                  onSetDefault: _setDefault,
                  onRevert: widget.target.pendingEdit == null
                      ? null
                      : widget.onRevert,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_prepareError != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Could not open the value: $_prepareError',
          style: AppTheme.ui(size: 11.5, color: AppColors.error),
        ),
      );
    }
    if (!_ready) {
      if (!_showSpinner) return const SizedBox.shrink();
      return Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 1.6,
            color: AppColors.accent,
          ),
        ),
      );
    }
    return _editorBody();
  }

  Widget _editorBody() => switch (_state) {
    BoolEditorState s => BoolBody(
      value: s.value,
      canBeNull: widget.target.canBeNull,
      onChange: (v) => setState(() => s.value = v),
      onNull: () => widget.onCommit(const CellLiteral(null)),
    ),
    MomentEditorState s => _momentBody(s),
    NumberEditorState s => NumberBody(
      controller: s.controller,
      focus: _focus,
      intOnly: widget.kind.label == 'int',
      onChanged: () => setState(() {}),
    ),
    TextEditorState s => TextBody(
      controller: s.controller,
      focus: _focus,
      isJson: s.isJson,
      onChanged: () => setState(() {
        // Clear the stale JSON error as soon as the user starts typing.
        if (s.jsonError != null) s.jsonError = null;
      }),
      error: s.isJson ? s.jsonError : null,
    ),
  };

  Widget _momentBody(MomentEditorState s) {
    final id = widget.kind.id;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MonoValueLine(
          kind: id,
          moment: s.value,
          tz: s.tz,
          withTz: s.withTz,
          onChange: (dt) => setState(() => s.value = dt),
          onTzChange: (tz) => setState(() => s.tz = tz),
        ),
        QuickActionsRow(children: _quickActionsFor(id)),
        Expanded(child: _momentInnerBody(s, id)),
      ],
    );
  }

  List<QuickAction> _quickActionsFor(KindId id) => switch (id) {
    KindId.date => [
      QuickAction(
        label: 'Today',
        icon: Hgi.calendar01,
        primary: true,
        onTap: () => _setToday(zeroTime: true),
      ),
      QuickAction(label: '−1 day', onTap: () => _shiftDate(days: -1)),
      QuickAction(label: '+1 day', onTap: () => _shiftDate(days: 1)),
    ],
    KindId.time => [
      QuickAction(
        label: 'Now',
        icon: Hgi.flash,
        primary: true,
        onTap: _setToNow,
      ),
      QuickAction(label: 'round :00', onTap: _roundHour),
      QuickAction(label: '+1 hour', onTap: () => _shiftHour(hours: 1)),
    ],
    KindId.datetime => [
      QuickAction(
        label: 'Now',
        icon: Hgi.flash,
        primary: true,
        onTap: _setToNow,
      ),
      QuickAction(label: 'Today 00:00', onTap: () => _setToday(zeroTime: true)),
      QuickAction(label: 'Tomorrow', onTap: () => _shiftDate(days: 1)),
    ],
    _ => const [],
  };

  Widget _momentInnerBody(MomentEditorState s, KindId id) => switch (id) {
    KindId.date => CalendarBody(
      initial: s.value,
      resetTick: _resetTick,
      onChange: (d) =>
          setState(() => s.value = DateTime(d.year, d.month, d.day)),
    ),
    KindId.datetime => DateTimeBody(
      initial: s.value,
      resetTick: _resetTick,
      onChange: (dt) => setState(() => s.value = dt),
    ),
    _ => const SizedBox.shrink(),
  };
}
