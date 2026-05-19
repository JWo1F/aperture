import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:postgres/postgres.dart';

import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import 'common.dart';
import 'json_spans.dart';

/// What the editor produced. `null` means the dialog was dismissed without
/// committing anything (Cancel, click outside, Esc).
sealed class EditorOutcome {
  const EditorOutcome();
}

/// User picked NULL / DEFAULT / typed a new value.
class EditorEdit extends EditorOutcome {
  const EditorEdit(this.value);
  final CellEditValue value;
}

/// User asked to drop a pending edit.
class EditorRevert extends EditorOutcome {}

/// Opens the value editor over a cell. If [editable] is false the modal acts
/// purely as a viewer (Close-only footer) and resolves to null.
Future<EditorOutcome?> showValueEditor(
  BuildContext context, {
  required String columnName,
  required dynamic rawValue,
  required bool editable,
  CellEditValue? pendingEdit,
}) {
  return showDialog<EditorOutcome>(
    context: context,
    barrierColor: const Color(0x88000000),
    builder: (_) => Dialog(
      backgroundColor: AppColors.surface,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: Radii.brLg,
        side: BorderSide(color: AppColors.borderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 600),
        child: _Editor(
          columnName: columnName,
          rawValue: rawValue,
          editable: editable,
          pendingEdit: pendingEdit,
        ),
      ),
    ),
  );
}

// --- Type detection ---------------------------------------------------

class _ValueType {
  const _ValueType(this.label, this.color, this.isJson);
  final String label;
  final Color color;
  final bool isJson;
}

_ValueType _typeOf(dynamic raw) {
  if (raw == null) return const _ValueType('null', AppColors.textMuted, false);
  if (raw is Map) return const _ValueType('json', AppColors.sqlString, true);
  if (raw is List) {
    return const _ValueType('array', AppColors.sqlString, true);
  }
  if (raw is bool) return const _ValueType('bool', AppColors.sqlFunction, false);
  if (raw is int || raw is BigInt) {
    return const _ValueType('int', AppColors.sqlNumber, false);
  }
  if (raw is num) {
    return const _ValueType('number', AppColors.sqlNumber, false);
  }
  if (raw is DateTime) {
    return const _ValueType('datetime', AppColors.info, false);
  }
  if (raw is UndecodedBytes) {
    return _ValueType(
      raw.isBinary ? 'bytea' : 'oid:${raw.typeOid}',
      AppColors.textMuted,
      false,
    );
  }
  return const _ValueType('string', AppColors.textSecondary, false);
}

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

// --- JSON highlight controller ----------------------------------------

class _JsonHighlightController extends TextEditingController {
  _JsonHighlightController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    return TextSpan(style: base, children: jsonSpans(text, base));
  }
}

// --- Editor body -------------------------------------------------------

class _Editor extends StatefulWidget {
  const _Editor({
    required this.columnName,
    required this.rawValue,
    required this.editable,
    required this.pendingEdit,
  });

  final String columnName;
  final dynamic rawValue;
  final bool editable;
  final CellEditValue? pendingEdit;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  late final _ValueType _type;
  late String _initial;

  @override
  void initState() {
    super.initState();
    _type = _typeOf(widget.rawValue);
    _initial = _initialText(widget.rawValue, widget.pendingEdit);
    _controller = _type.isJson
        ? _JsonHighlightController(text: _initial)
        : TextEditingController(text: _initial);
    _focus = FocusNode();
    if (widget.editable) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _isDirty => _controller.text != _initial;
  bool get _hasPending => widget.pendingEdit != null;

  void _save() {
    Navigator.of(context).pop(EditorEdit(CellLiteral(_controller.text)));
  }

  void _setNull() {
    Navigator.of(context).pop(const EditorEdit(CellLiteral(null)));
  }

  void _setDefault() {
    Navigator.of(context).pop(const EditorEdit(CellDefault()));
  }

  void _revert() {
    Navigator.of(context).pop(EditorRevert());
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _controller.text));
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape):
            () => Navigator.of(context).pop(),
        if (widget.editable)
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _save,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            columnName: widget.columnName,
            type: _type,
            edited: _hasPending,
            pendingKind: _pendingKindLabel(widget.pendingEdit),
            onCopy: _copy,
            onClose: () => Navigator.of(context).pop(),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: _EditorArea(
              controller: _controller,
              focus: _focus,
              readOnly: !widget.editable,
              onChanged: () => setState(() {}),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          _Footer(
            editable: widget.editable,
            hasPending: _hasPending,
            isDirty: _isDirty,
            onSave: _save,
            onCancel: () => Navigator.of(context).pop(),
            onSetNull: _setNull,
            onSetDefault: _setDefault,
            onRevert: _revert,
          ),
        ],
      ),
    );
  }
}

String? _pendingKindLabel(CellEditValue? pending) {
  return switch (pending) {
    CellLiteral(:final value) when value == null => 'NULL',
    CellLiteral() => 'edited',
    CellDefault() => 'DEFAULT',
    null => null,
  };
}

class _Header extends StatelessWidget {
  const _Header({
    required this.columnName,
    required this.type,
    required this.edited,
    required this.pendingKind,
    required this.onCopy,
    required this.onClose,
  });

  final String columnName;
  final _ValueType type;
  final bool edited;
  final String? pendingKind;
  final VoidCallback onCopy;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, 12, 10, 12),
      child: Row(
        children: [
          const Icon(
            Icons.edit_note_outlined,
            size: 16,
            color: AppColors.accent,
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Text(
              columnName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.mono(size: 12.5, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          _Tag(label: type.label, color: type.color),
          if (edited) ...[
            const SizedBox(width: 6),
            _Tag(label: pendingKind ?? 'edited', color: AppColors.accent),
          ],
          const Spacer(),
          IconAction(icon: Icons.copy, tooltip: 'Copy', onPressed: onCopy),
          IconAction(icon: Icons.close, tooltip: 'Close', onPressed: onClose),
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: Radii.brSm,
      ),
      child: Text(
        label,
        style: AppTheme.mono(size: 10, color: color, weight: FontWeight.w600),
      ),
    );
  }
}

class _EditorArea extends StatelessWidget {
  const _EditorArea({
    required this.controller,
    required this.focus,
    required this.readOnly,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool readOnly;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.md,
        vertical: Insets.sm,
      ),
      child: Scrollbar(
        child: TextField(
          controller: controller,
          focusNode: focus,
          readOnly: readOnly,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          cursorColor: AppColors.accent,
          onChanged: (_) => onChanged(),
          style: AppTheme.mono(size: 12.5, color: AppColors.textPrimary),
          decoration: const InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.editable,
    required this.hasPending,
    required this.isDirty,
    required this.onSave,
    required this.onCancel,
    required this.onSetNull,
    required this.onSetDefault,
    required this.onRevert,
  });

  final bool editable;
  final bool hasPending;
  final bool isDirty;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final VoidCallback onSetNull;
  final VoidCallback onSetDefault;
  final VoidCallback onRevert;

  @override
  Widget build(BuildContext context) {
    if (!editable) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Insets.lg, vertical: 12),
        child: Row(
          children: [
            const Spacer(),
            AppButton(label: 'Close', onPressed: onCancel),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.lg, vertical: 12),
      child: Row(
        children: [
          if (hasPending) ...[
            AppButton(
              label: 'Revert',
              icon: Icons.undo,
              onPressed: onRevert,
            ),
            const SizedBox(width: Insets.sm),
          ],
          AppButton(
            label: 'Set NULL',
            icon: Icons.not_interested,
            onPressed: onSetNull,
          ),
          const SizedBox(width: Insets.sm),
          AppButton(
            label: 'Set DEFAULT',
            icon: Icons.settings_backup_restore,
            onPressed: onSetDefault,
          ),
          const Spacer(),
          AppButton(label: 'Cancel', onPressed: onCancel),
          const SizedBox(width: Insets.sm),
          AppButton(
            label: 'Save',
            icon: Icons.check,
            primary: true,
            onPressed: isDirty ? onSave : null,
          ),
        ],
      ),
    );
  }
}
