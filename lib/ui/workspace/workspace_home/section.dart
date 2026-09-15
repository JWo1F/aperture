import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import '../../widgets/common.dart';

/// Eyebrow-labelled wrapper around a section's child column. The count chip is
/// suppressed when [count] is zero so an empty list shows just its title.
class HomeSection extends StatelessWidget {
  const HomeSection({
    super.key,
    required this.title,
    required this.count,
    required this.child,
  });

  final String title;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 9),
          child: Row(
            children: [
              Text(title.toUpperCase(), style: AppTheme.eyebrow()),
              if (count > 0) ...[
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: const BorderRadius.all(Radii.xs),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    '$count',
                    style: AppTheme.mono(size: 9.5, color: AppColors.textMuted),
                  ),
                ),
              ],
            ],
          ),
        ),
        child,
      ],
    );
  }
}

class HomeSectionEmpty extends StatelessWidget {
  const HomeSectionEmpty({
    super.key,
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: Radii.brSm,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: AppColors.text4),
          const SizedBox(height: 9),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTheme.ui(
              size: 11.5,
              weight: FontWeight.w400,
              color: AppColors.textMuted,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    );
  }
}

class HomeTextAction extends StatelessWidget {
  const HomeTextAction({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Hgi.add01,
            size: 13,
            color: hovering ? AppColors.accentHover : AppColors.accent,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTheme.ui(
              size: 11.5,
              weight: FontWeight.w500,
              color: hovering ? AppColors.accentHover : AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}
