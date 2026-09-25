import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import '../../widgets/common.dart';

class WelcomeHero extends StatelessWidget {
  const WelcomeHero({
    super.key,
    required this.onSearch,
    required this.onNew,
    required this.stacked,
  });

  final VoidCallback onSearch;
  final VoidCallback onNew;

  /// Puts the actions under the title instead of beside it.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final title = Row(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(18)),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.22),
                blurRadius: 28,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(18)),
            child: Image.asset(
              'assets/brand/app_icon.png',
              width: 76,
              height: 76,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Aperture',
                style: AppTheme.ui(
                  size: 30,
                  weight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.9,
                ).copyWith(height: 1.1),
              ),
              const SizedBox(height: 6),
              Text(
                'A close look at PostgreSQL and SQLite.',
                style: AppTheme.ui(
                  size: 13.5,
                  weight: FontWeight.w400,
                  color: AppColors.textSecondary,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _HeroButton(
          icon: Hgi.search01,
          label: 'Search',
          shortcut: '⌘K',
          onTap: onSearch,
        ),
        _HeroButton(
          icon: Hgi.add01,
          label: 'New connection',
          primary: true,
          onTap: onNew,
        ),
      ],
    );

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [title, const SizedBox(height: 18), actions],
      );
    }
    return Row(
      children: [
        Expanded(child: title),
        const SizedBox(width: 24),
        actions,
      ],
    );
  }
}

/// Hover swaps colours instantly; `AppButton` cross-fades, and this screen
/// carries no motion.
class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.shortcut,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final String? shortcut;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) {
        final Color bg;
        final Color fg;
        final Color border;
        if (primary) {
          bg = hovering ? AppColors.accentHover : AppColors.accent;
          fg = Colors.white;
          border = bg;
        } else {
          bg = hovering ? AppColors.surfaceHover : AppColors.surface;
          fg = AppColors.textPrimary;
          border = hovering ? AppColors.borderStrong : AppColors.border;
        }
        return Container(
          height: 34,
          padding: EdgeInsets.only(left: 12, right: shortcut == null ? 14 : 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: Radii.brSm,
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 7),
              Text(
                label,
                style: AppTheme.ui(
                  size: 12.5,
                  weight: FontWeight.w500,
                  color: fg,
                  letterSpacing: -0.1,
                ),
              ),
              if (shortcut != null) ...[
                const SizedBox(width: 9),
                KbdChip(shortcut!, onAccent: primary),
              ],
            ],
          ),
        );
      },
    );
  }
}
