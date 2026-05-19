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
/// syntax highlighting + room, booleans become a two-button toggle, numbers
/// stay compact single-line.
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
}) {
  final kind = _kindFor(originalValue);
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

// --- Type / shape ------------------------------------------------------

class _Kind {
  const _Kind({
    required this.label,
    required this.color,
    required this.size,
    required this.multiline,
    required this.highlightJson,
    required this.isBool,
  });
  final String label;
  final Color color;
  final Size size;
  final bool multiline;
  final bool highlightJson;
  final bool isBool;
}

_Kind _kindFor(dynamic v) {
  if (v is bool) {
    return const _Kind(
      label: 'bool',
      color: AppColors.sqlFunction,
      size: Size(240, 120),
      multiline: false,
      highlightJson: false,
      isBool: true,
    );
  }
  if (v is Map) {
    return const _Kind(
      label: 'json',
      color: AppColors.sqlString,
      size: Size(540, 340),
      multiline: true,
      highlightJson: true,
      isBool: false,
    );
  }
  if (v is List) {
    return const _Kind(
      label: 'array',
      color: AppColors.sqlString,
      size: Size(540, 340),
      multiline: true,
      highlightJson: true,
      isBool: false,
    );
  }
  if (v is int || v is BigInt) {
    return const _Kind(
      label: 'int',
      color: AppColors.sqlNumber,
      size: Size(260, 132),
      multiline: false,
      highlightJson: false,
      isBool: false,
    );
  }
  if (v is num) {
    return const _Kind(
      label: 'number',
      color: AppColors.sqlNumber,
      size: Size(260, 132),
      multiline: false,
      highlightJson: false,
      isBool: false,
    );
  }
  if (v is DateTime) {
    return const _Kind(
      label: 'datetime',
      color: AppColors.info,
      size: Size(320, 132),
      multiline: false,
      highlightJson: false,
      isBool: false,
    );
  }
  if (v is UndecodedBytes) {
    return const _Kind(
      label: 'bytes',
      color: AppColors.textMuted,
      size: Size(380, 220),
      multiline: true,
      highlightJson: false,
      isBool: false,
    );
  }
  // string / null / unknown
  return const _Kind(
    label: 'string',
    color: AppColors.textSecondary,
    size: Size(380, 220),
    multiline: true,
    highlightJson: false,
    isBool: false,
  );
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
  late final TextEditingController _text;
  final FocusNode _focus = FocusNode();
  late bool? _bool;
  late final String _baselineText;
  late final bool? _baselineBool;

  @override
  void initState() {
    super.initState();
    _baselineText = _initialText(widget.originalValue, widget.pendingEdit);
    _baselineBool = _initialBool(widget.originalValue, widget.pendingEdit);
    _text = widget.kind.highlightJson
        ? JsonHighlightController(text: _baselineText)
        : TextEditingController(text: _baselineText);
    _bool = _baselineBool;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.kind.isBool) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _isDirty {
    if (widget.kind.isBool) return _bool != _baselineBool;
    return _text.text != _baselineText;
  }

  void _save() {
    if (widget.kind.isBool) {
      if (_bool == null) return;
      widget.onCommit(CellLiteral(_bool! ? 'true' : 'false'));
    } else {
      widget.onCommit(CellLiteral(_text.text));
    }
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
              Expanded(
                child: widget.kind.isBool
                    ? _BoolBody(
                        value: _bool,
                        onChange: (v) => setState(() => _bool = v),
                      )
                    : _TextBody(
                        controller: _text,
                        focus: _focus,
                        multiline: widget.kind.multiline,
                        onChanged: () => setState(() {}),
                      ),
              ),
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
}

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
            decoration: BoxDecoration(color: kind.color, shape: BoxShape.circle),
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
        style: AppTheme.mono(size: 9.5, color: color, weight: FontWeight.w700),
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
            tooltip:
                canBeNull ? 'Set NULL' : 'Column is NOT NULL',
            onPressed: canBeNull ? onSetNull : null,
          ),
          const SizedBox(width: 2),
          IconAction(
            icon: Icons.settings_backup_restore,
            tooltip:
                hasDefault ? 'Set DEFAULT' : 'Column has no default',
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
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool multiline;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: TextField(
        controller: controller,
        focusNode: focus,
        maxLines: multiline ? null : 1,
        expands: multiline,
        textAlignVertical: TextAlignVertical.top,
        cursorColor: AppColors.accent,
        onChanged: (_) => onChanged(),
        style: AppTheme.mono(size: 12, color: AppColors.textPrimary),
        decoration: const InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
        ),
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
