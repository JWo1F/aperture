import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../widgets/common.dart';

/// Short 1×14 hairline used *within* a toolbar group — e.g. between the
/// sidebar toggle and the back/forward pair. Matches the design's `.rail`.
class TbRail extends StatelessWidget {
  const TbRail({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: AppColors.hairline,
    );
  }
}

/// Full-height 1px hairline used *between* toolbar groups — sits flush with
/// the surrounding group padding so it visually divides the run of icons
/// instead of nesting inside one of them. Matches the design's `.tb-rail`.
class TbGroupRail extends StatelessWidget {
  const TbGroupRail({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: AppColors.hairline,
    );
  }
}

/// 26×26 ghost icon button used throughout the toolbar.
class TbIcon extends StatelessWidget {
  const TbIcon({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: Hoverable(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onTap: onPressed,
        builder: (context, hovering) {
          final Color fg = enabled
              ? (hovering ? AppColors.textPrimary : AppColors.textMuted)
              : AppColors.textMuted.withValues(alpha: 0.4);
          final Color bg = hovering && enabled
              ? AppColors.surfaceHover
              : AppColors.surfaceHover.withValues(alpha: 0);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, borderRadius: Radii.brSm),
            child: Icon(icon, size: 14, color: fg),
          );
        },
      ),
    );
  }
}

/// Wide ⌘K search trigger styled as a flat input — surface bg, hairline
/// border, magnifier glyph, hint text, kbd chip.
class TbSearch extends StatelessWidget {
  const TbSearch({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Find tables, queries…  ⌘K',
      child: Hoverable(
        onTap: onTap,
        builder: (context, hovering) => Container(
          height: 24,
          padding: const EdgeInsets.only(left: 10, right: 5),
          decoration: BoxDecoration(
            color: hovering ? AppColors.surfaceHover : AppColors.surface,
            borderRadius: Radii.brSm,
            border: Border.all(
              color: hovering ? AppColors.borderStrong : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 12, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Find tables, queries…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.ui(
                    size: 11,
                    color: AppColors.textMuted,
                    weight: FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const _TbKbd(parts: ['⌘', 'K']),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tiny kbd group rendered with the design's surface-2 chip styling.
class _TbKbd extends StatelessWidget {
  const _TbKbd({required this.parts});

  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          // No `alignment` here: a Container with an alignment expands to
          // fill bounded parent constraints — the 24px search field — so the
          // chip would balloon to the full field height. Without it the
          // Container hugs the glyph; horizontal centring for the narrow `K`
          // comes from the Text's own textAlign inside minWidth.
          Container(
            constraints: const BoxConstraints(minWidth: 14),
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              parts[i],
              textAlign: TextAlign.center,
              // height: 1.0 — AppTheme.ui's 1.35 line box would inflate the
              // chip past the glyph.
              style: AppTheme.ui(
                size: 9,
                color: AppColors.textSecondary,
                weight: FontWeight.w500,
              ).copyWith(height: 1.0),
            ),
          ),
        ],
      ],
    );
  }
}
