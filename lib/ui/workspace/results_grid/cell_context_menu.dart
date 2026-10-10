import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/cell_edit.dart';
import '../../../models/db_object.dart';
import '../../../models/value_format.dart';
import '../../widgets/context_menu.dart';
import '../../../theme/hugeicons.dart';
import '../../widgets/command_key.dart';

/// The cell a results-grid right-click menu acts on.
class CellMenuTarget {
  const CellMenuTarget({
    required this.columnName,
    required this.original,
    required this.isInsert,
    required this.isDeleted,
    required this.pending,
    required this.meta,
    required this.foreignKey,
    required this.findRowOwner,
    required this.editable,
  });

  final String columnName;
  final Object? original;
  final bool isInsert;
  final bool isDeleted;
  final CellEditValue? pending;
  final DbColumn? meta;
  final DbForeignKey? foreignKey;
  final DbTable? findRowOwner;
  final bool editable;
}

/// Actions a results-grid cell menu can dispatch. Each is pre-bound by the
/// grid to the target cell's (row, column); a null callback hides or disables
/// the corresponding menu item.
class CellMenuActions {
  const CellMenuActions({
    this.onOpenEditor,
    this.onSetValue,
    this.onRevert,
    this.onDeleteRow,
    this.onRestoreRow,
    this.onDuplicateRow,
    this.onAddRow,
    this.onFollowForeignKey,
    this.onFindRow,
    this.onAddFilter,
    this.onSetSort,
  });

  /// Opens the type-aware cell picker. Non-null exactly when [onSetValue] is.
  final VoidCallback? onOpenEditor;

  /// Commits a literal NULL or a DEFAULT directive to the cell. Non-null when
  /// the cell is editable.
  final void Function(CellEditValue value)? onSetValue;
  final VoidCallback? onRevert;
  final VoidCallback? onDeleteRow;
  final VoidCallback? onRestoreRow;
  final VoidCallback? onDuplicateRow;

  /// Queues a blank pending insert (all columns DEFAULT) below the row.
  final VoidCallback? onAddRow;
  final VoidCallback? onFollowForeignKey;
  final VoidCallback? onFindRow;
  final void Function(bool not)? onAddFilter;
  final void Function(bool descending)? onSetSort;
}

/// Builds and shows the results-grid cell context menu at [position].
void showCellContextMenu(
  BuildContext context, {
  required Offset position,
  required CellMenuTarget target,
  required CellMenuActions actions,
}) {
  final columnName = target.columnName;
  final pending = target.pending;
  final canBeNull = target.meta?.nullable ?? true;
  final hasDefault = target.meta?.hasDefault ?? false;

  final String? displayValue = pending is CellLiteral
      ? pending.value
      : (pending is CellDefault
            ? null
            : (target.isInsert ? null : formatCellValue(target.original)));

  void copy(String text) => Clipboard.setData(ClipboardData(text: text));

  final entries = <CmEntry>[
    CmItem(
      icon: Hgi.copy01,
      label: 'Copy value',
      shortcut: commandLabel('C'),
      onTap: () => copy(displayValue ?? 'NULL'),
    ),
    if (!target.isInsert &&
        (target.original is Map || target.original is List))
      CmItem(
        icon: Hgi.braces,
        label: 'Copy pretty JSON',
        onTap: () {
          try {
            copy(const JsonEncoder.withIndent('  ').convert(target.original));
          } catch (_) {}
        },
      ),
    CmItem(
      icon: Hgi.tag01,
      label: 'Copy column name',
      onTap: () => copy(columnName),
    ),
    CmItem(
      icon: Hgi.textAlignLeft,
      label: 'Copy as "$columnName = …"',
      onTap: () => copy('$columnName = ${displayValue ?? 'NULL'}'),
    ),
    const CmDivider(),
    if (!target.isInsert &&
        target.foreignKey != null &&
        actions.onFollowForeignKey != null) ...[
      CmItem(
        icon: Hgi.arrowUpRight01,
        label: 'Follow → ${target.foreignKey!.refQualified}',
        onTap: () => actions.onFollowForeignKey?.call(),
      ),
      const CmDivider(),
    ],
    if (!target.isInsert &&
        target.findRowOwner != null &&
        actions.onFindRow != null) ...[
      CmItem(
        icon: Hgi.search01,
        label: 'Find row in ${target.findRowOwner!.qualifiedKey}',
        onTap: () => actions.onFindRow?.call(),
      ),
      const CmDivider(),
    ],
    if (actions.onSetValue != null) ...[
      CmItem(
        icon: Hgi.edit02,
        label: 'Edit cell',
        shortcut: '⏎⏎',
        onTap: () => actions.onOpenEditor?.call(),
      ),
      CmItem(
        icon: Hgi.cancelCircle,
        label: canBeNull ? 'Set NULL' : 'Set NULL (column is NOT NULL)',
        enabled: canBeNull,
        onTap: () => actions.onSetValue!(const CellLiteral(null)),
      ),
      CmItem(
        icon: Hgi.reload,
        label: hasDefault ? 'Set DEFAULT' : 'Set DEFAULT (no default value)',
        enabled: hasDefault,
        onTap: () => actions.onSetValue!(const CellDefault()),
      ),
      if (actions.onRevert != null)
        CmItem(
          icon: Hgi.undo,
          label: 'Revert change',
          onTap: () => actions.onRevert?.call(),
        ),
      const CmDivider(),
    ],
    if (target.editable) ...[
      if (target.isInsert)
        CmItem(
          icon: Hgi.delete02,
          label: 'Discard new row',
          enabled: actions.onDeleteRow != null,
          danger: true,
          onTap: () => actions.onDeleteRow?.call(),
        )
      else if (target.isDeleted)
        CmItem(
          icon: Hgi.restoreBin,
          label: 'Restore row',
          enabled: actions.onRestoreRow != null,
          onTap: () => actions.onRestoreRow?.call(),
        )
      else
        CmItem(
          icon: Hgi.delete02,
          label: 'Delete row',
          enabled: actions.onDeleteRow != null,
          danger: true,
          onTap: () => actions.onDeleteRow?.call(),
        ),
      CmItem(
        icon: Hgi.copy02,
        label: 'Duplicate row',
        enabled: actions.onDuplicateRow != null && !target.isDeleted,
        onTap: () => actions.onDuplicateRow?.call(),
      ),
      CmItem(
        icon: Hgi.addSquare,
        label: 'Add new row',
        enabled: actions.onAddRow != null && !target.isDeleted,
        onTap: () => actions.onAddRow?.call(),
      ),
      const CmDivider(),
    ],
    if (!target.isInsert && actions.onAddFilter != null) ...[
      CmItem(
        icon: Hgi.filter,
        label: 'Filter: $columnName = value',
        onTap: () => actions.onAddFilter!(false),
      ),
      CmItem(
        icon: Hgi.ban,
        label: 'Filter: $columnName ≠ value',
        onTap: () => actions.onAddFilter!(true),
      ),
    ],
    if (actions.onSetSort != null) ...[
      CmItem(
        icon: Hgi.arrowUp01,
        label: 'Sort ascending',
        onTap: () => actions.onSetSort!(false),
      ),
      CmItem(
        icon: Hgi.arrowDown01,
        label: 'Sort descending',
        onTap: () => actions.onSetSort!(true),
      ),
    ],
  ];

  showContextMenu(context, globalPosition: position, entries: entries);
}
