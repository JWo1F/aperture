import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../widgets/code_editor.dart';
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
import 'tz_input.dart';
import 'value_line.dart';
import '../../theme/hugeicons.dart';

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
  late final EditorState _state;

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
      case KindId.text:
      case KindId.json:
      case KindId.array:
        // An array seeds as a Postgres array literal, not as JSON. The
        // grid paints `[1,2]` because that reads better in a cell, but
        // that is not a value the column accepts back — `SET tags =
        // '[1,2]'` is a malformed array literal. Seeding the braces form
        // means what the user sees is what gets written.
        final text = k == KindId.array
            ? initialArrayText(
                widget.target.originalValue,
                widget.target.pendingEdit,
              )
            : initialText(
                widget.target.originalValue,
                widget.target.pendingEdit,
              );
        final isJson = k == KindId.json;
        _state = TextEditorState(
          controller: isJson
              ? CodeEditorController(text: text, language: 'json')
              : TextEditingController(text: text),
          baseline: text,
          isJson: isJson,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focus.requestFocus();
        });
    }
  }

  @override
  void dispose() {
    _state.disposeResources();
    _focus.dispose();
    super.dispose();
  }

  bool get _isDirty => _state.isDirty;

  void _save() {
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
    if (widget.target.isPrimaryKey) return 'cannot edit primary key';
    switch (widget.kind.id) {
      case KindId.text:
        return '↵ commit · esc cancel';
      case KindId.bool:
        return 'esc cancel';
      case KindId.json:
      case KindId.array:
      case KindId.date:
      case KindId.time:
      case KindId.datetime:
        return '⌘↵ commit · esc cancel';
    }
  }

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
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 24,
                  offset: const Offset(0, 8),
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
                Header(target: widget.target, kind: widget.kind),
                Expanded(child: _buildBody()),
                Footer(
                  hasPending: widget.target.pendingEdit != null,
                  canSave: _isDirty,
                  canBeNull: widget.target.canBeNull,
                  hasDefault: widget.target.hasDefault,
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
      ),
    );
  }

  Widget _buildBody() => switch (_state) {
    BoolEditorState s => BoolBody(
      value: s.value,
      onChange: (v) => setState(() => s.value = v),
      onNull: () => widget.onCommit(const CellLiteral(null)),
    ),
    MomentEditorState s => _momentBody(s),
    TextEditorState s => _textOrNumberBody(s),
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
    KindId.time =>
      s.withTz
          ? Container(
              color: AppColors.bg,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: TzInput(
                value: s.tz,
                onChange: (tz) => setState(() => s.tz = tz),
              ),
            )
          : const SizedBox.shrink(),
    KindId.datetime => DateTimeBody(
      initial: s.value,
      withTz: s.withTz,
      tz: s.tz,
      resetTick: _resetTick,
      onChange: (dt) => setState(() => s.value = dt),
      onTzChange: (tz) => setState(() => s.tz = tz),
    ),
    _ => const SizedBox.shrink(),
  };

  Widget _textOrNumberBody(TextEditorState s) {
    final isNumber =
        widget.kind.label == 'number' || widget.kind.label == 'int';
    if (isNumber) {
      return NumberBody(
        controller: s.controller,
        focus: _focus,
        intOnly: widget.kind.label == 'int',
        onChanged: () => setState(() {}),
      );
    }
    return TextBody(
      controller: s.controller,
      focus: _focus,
      multiline: widget.kind.multiline,
      onChanged: () => setState(() {
        // Clear the stale JSON error as soon as the user starts typing.
        if (s.jsonError != null) s.jsonError = null;
      }),
      inputFormatters: widget.kind.inputFormatters,
      error: s.isJson ? s.jsonError : null,
    );
  }
}
