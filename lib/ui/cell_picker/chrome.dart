import 'package:flutter/material.dart';

import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'kinds.dart';
import 'target.dart';

class Header extends StatelessWidget {
  const Header({super.key, required this.target, required this.kind});

  final CellEditTarget target;
  final Kind kind;

  ({String label, Color color})? _flag() {
    if (target.isPrimaryKey) {
      return (label: 'read-only', color: AppColors.warn);
    }
    return switch (target.pendingEdit) {
      CellLiteral(:final value) when value == null => (
        label: 'NULL',
        color: AppColors.accent,
      ),
      CellLiteral() => (label: 'edited', color: AppColors.accent),
      CellDefault() => (label: 'DEFAULT', color: AppColors.accent),
      null => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final flag = _flag();
    final typeLabel = target.columnDataType ?? kind.label;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Row(
        children: [
          if (target.isPrimaryKey) ...[
            Icon(Icons.vpn_key, size: 10, color: AppColors.accent),
            const SizedBox(width: 6),
          ] else if (target.isForeignKey) ...[
            Icon(Icons.north_east, size: 10, color: AppColors.tFk),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              target.columnName,
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
              style: AppTheme.mono(size: 10.5, color: AppColors.textMuted),
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

class Footer extends StatelessWidget {
  const Footer({
    super.key,
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
              style: AppTheme.mono(size: 10.5, color: AppColors.textMuted),
            ),
          ),
          if (hasPending) ...[
            _PillButton(label: 'revert', onPressed: onRevert),
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
          _PillButton(label: 'cancel', onPressed: onCancel),
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
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onTap: enabled ? onPressed : null,
      builder: (context, hovering) {
        final Color bg = primary
            ? (enabled
                  ? (hovering ? AppColors.accentHover : AppColors.accent)
                  : AppColors.accent.withValues(alpha: 0.4))
            : (hovering && enabled
                  ? AppColors.surfaceHover
                  : AppColors.surfaceHover.withValues(alpha: 0));
        final Color border = primary
            ? Colors.transparent
            : (enabled ? AppColors.border : AppColors.borderSoft);
        final Color fg = primary
            ? Colors.white
            : (enabled
                  ? (hovering ? AppColors.textPrimary : AppColors.textSecondary)
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
