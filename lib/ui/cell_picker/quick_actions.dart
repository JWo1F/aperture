import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../widgets/common.dart';

const double quickActionsHeight = 32;

/// Row of small action chips (Now / Today / shift) under the value line. The
/// `primary` action is tinted with the accent, the others stay quiet.
class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key, required this.children});

  final List<QuickAction> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: quickActionsHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            children[i],
          ],
        ],
      ),
    );
  }
}

class QuickAction extends StatelessWidget {
  const QuickAction({
    super.key,
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
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) {
        final Color fg = primary
            ? AppColors.accent
            : (hovering ? AppColors.textPrimary : AppColors.textSecondary);
        final Color hoverBg = primary
            ? AppColors.accentSoft
            : AppColors.surfaceHover;
        return Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: hovering ? hoverBg : hoverBg.withValues(alpha: 0),
            borderRadius: Radii.brSm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 11, color: fg),
                const SizedBox(width: 5),
              ],
              Text(label, style: AppTheme.ui(size: 11.5, color: fg)),
            ],
          ),
        );
      },
    );
  }
}
