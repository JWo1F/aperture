import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Bordered card with a fixed-height title bar. Rows inside are separated by
/// hairlines rather than boxed individually, so a panel reads as one list.
class HomePanel extends StatelessWidget {
  const HomePanel({
    super.key,
    required this.title,
    required this.child,
    this.count,
    this.trailing,
  });

  final String title;
  final int? count;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: Radii.brMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Text(
                  title,
                  style: AppTheme.ui(
                    size: 12,
                    weight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.1,
                  ),
                ),
                if (count != null && count! > 0) ...[
                  const SizedBox(width: 7),
                  Text(
                    '$count',
                    style: AppTheme.mono(
                      size: 10.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                const Spacer(),
                ?trailing,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// One clickable line inside a [HomePanel]. Hover swaps the fill instantly —
/// the home screen carries no motion.
class HomePanelRow extends StatelessWidget {
  const HomePanelRow({
    super.key,
    required this.child,
    this.onTap,
    this.height = 34,
    this.divider = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double height;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      builder: (context, hovering) => Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: hovering && onTap != null
              ? AppColors.surfaceHover
              : AppColors.surfaceHover.withValues(alpha: 0),
          border: divider
              ? Border(top: BorderSide(color: AppColors.borderSoft))
              : null,
        ),
        child: child,
      ),
    );
  }
}

class HomePanelEmpty extends StatelessWidget {
  const HomePanelEmpty({
    super.key,
    required this.message,
    this.icon,
    this.glyph,
    this.action,
  }) : assert(
         (icon == null) != (glyph == null),
         'Provide exactly one of icon or glyph',
       );

  final IconData? icon;

  /// A painted mark in place of [icon] — the shared table glyph.
  final Widget Function(Color color, double size)? glyph;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Row(
        children: [
          glyph?.call(AppColors.text4, 16) ??
              Icon(icon, size: 16, color: AppColors.text4),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTheme.ui(
                size: 11.5,
                weight: FontWeight.w400,
                color: AppColors.textMuted,
                letterSpacing: 0,
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(width: 10), action!],
        ],
      ),
    );
  }
}

/// Accent-coloured inline link, used for panel header and empty-state
/// actions.
class HomeLink extends StatelessWidget {
  const HomeLink({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) {
        final color = hovering ? AppColors.accentHover : AppColors.accent;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: AppTheme.ui(
                size: 11.5,
                weight: FontWeight.w500,
                color: color,
                letterSpacing: 0,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Thin proportional bar — the storage share of one relation or schema.
class ShareBar extends StatelessWidget {
  const ShareBar({
    super.key,
    required this.fraction,
    required this.color,
    this.width = 64,
  });

  final double fraction;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 4,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: const BorderRadius.all(Radius.circular(2)),
      ),
      child: FractionallySizedBox(
        widthFactor: fraction.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.all(Radius.circular(2)),
          ),
        ),
      ),
    );
  }
}
