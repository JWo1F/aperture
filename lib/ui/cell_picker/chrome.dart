import 'package:flutter/material.dart';

import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../../theme/hugeicons.dart';
import '../widgets/common.dart';
import 'kinds.dart';
import 'target.dart';

const double headerHeight = 30;
const double footerHeight = 38;

class Header extends StatelessWidget {
  const Header({super.key, required this.target, required this.kind});

  final CellEditTarget target;
  final Kind kind;

  ({String label, Color color})? _flag() {
    if (target.isPrimaryKey) {
      return (label: 'Primary key', color: AppColors.warn);
    }
    return switch (target.pendingEdit) {
      CellLiteral(:final value) when value == null => (
        label: 'NULL',
        color: AppColors.accent,
      ),
      CellLiteral() => (label: 'Edited', color: AppColors.accent),
      CellDefault() => (label: 'DEFAULT', color: AppColors.accent),
      null => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final flag = _flag();
    final typeLabel = target.columnDataType ?? kind.label;
    return Container(
      height: headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          if (target.isPrimaryKey) ...[
            Icon(Hgi.key01, size: 11, color: AppColors.warn),
            const SizedBox(width: 6),
          ] else if (target.isForeignKey) ...[
            Icon(Hgi.arrowUpRight01, size: 11, color: AppColors.tFk),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              target.columnName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.mono(
                size: 11.5,
                color: AppColors.textPrimary,
                weight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              typeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.mono(size: 11, color: AppColors.textMuted),
            ),
          ),
          if (flag != null) ...[
            const Spacer(),
            const SizedBox(width: 8),
            Text(flag.label, style: AppTheme.ui(size: 11, color: flag.color)),
          ],
        ],
      ),
    );
  }
}

/// Value shortcuts on the left, Save on the right. NULL and DEFAULT are
/// left out entirely when the column forbids them rather than shown
/// disabled; closing is Esc or a click outside, so there is no Cancel.
class Footer extends StatelessWidget {
  const Footer({
    super.key,
    required this.canSave,
    required this.showNull,
    required this.showDefault,
    required this.onSave,
    required this.onSetNull,
    required this.onSetDefault,
    required this.onRevert,
  });

  final bool canSave;
  final bool showNull;
  final bool showDefault;
  final VoidCallback onSave;
  final VoidCallback onSetNull;
  final VoidCallback onSetDefault;

  /// Null when the cell has no pending edit to revert.
  final VoidCallback? onRevert;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: footerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          if (showNull) _TextAction(label: 'NULL', onTap: onSetNull),
          if (showDefault) _TextAction(label: 'Default', onTap: onSetDefault),
          if (onRevert != null) _TextAction(label: 'Revert', onTap: onRevert!),
          const Spacer(),
          _SaveButton(onTap: canSave ? onSave : null),
        ],
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hovering
              ? AppColors.surfaceHover
              : AppColors.surfaceHover.withValues(alpha: 0),
          borderRadius: Radii.brSm,
        ),
        child: Text(
          label,
          style: AppTheme.ui(
            size: 11.5,
            color: hovering ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Hoverable(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onTap: onTap,
      builder: (context, hovering) => Container(
        height: 24,
        padding: const EdgeInsets.only(left: 10, right: 4),
        decoration: BoxDecoration(
          color: !enabled
              ? AppColors.accent.withValues(alpha: 0.4)
              : (hovering ? AppColors.accentHover : AppColors.accent),
          borderRadius: Radii.brSm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Save',
              style: AppTheme.ui(
                size: 11.5,
                color: Colors.white.withValues(alpha: enabled ? 1 : 0.7),
              ),
            ),
            const SizedBox(width: 6),
            const KbdChip('⌘↵', size: 9.5, onAccent: true),
          ],
        ),
      ),
    );
  }
}
