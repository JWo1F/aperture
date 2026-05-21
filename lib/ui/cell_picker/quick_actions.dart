import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../widgets/common.dart';

/// Row of small action chips (Now / Today / shift) under the value line. The
/// `primary` action lights in the accent, others stay quiet.
class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key, required this.children});

  final List<QuickAction> children;

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
              Container(width: 1, height: 28, color: AppColors.hairline),
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
    final Color fg = primary ? AppColors.accent : AppColors.textSecondary;
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) {
        final Color bg = primary && hovering
            ? AppColors.accentSoft
            : (hovering ? AppColors.sidebarRowHover : Colors.transparent);
        final Color fgHover = hovering && !primary ? AppColors.textPrimary : fg;
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
