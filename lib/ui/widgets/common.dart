import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Hairline vertical rail used to separate logical groups in compact
/// toolbars (table view, query editor, …).
class Rail extends StatelessWidget {
  const Rail({super.key, this.height = 18});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: AppColors.border,
    );
  }
}

/// Generic hover wrapper: tracks a hover bool and exposes it to a
/// builder, so the dozen-plus widgets that need a "hovering?" state for
/// background swaps don't each carry the same MouseRegion + setState
/// scaffolding.
///
/// The widget owns the [GestureDetector] for [onTap] so the hit area
/// matches the visible region cleanly. Builders should return a widget
/// that paints differently based on [hovering] — they do not need their
/// own MouseRegion.
class Hoverable extends StatefulWidget {
  const Hoverable({
    super.key,
    required this.builder,
    this.onTap,
    this.onSecondaryTap,
    this.onSecondaryTapDown,
    this.onTapDown,
    this.onTertiaryTapUp,
    this.cursor = SystemMouseCursors.click,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget Function(BuildContext context, bool hovering) builder;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final GestureTapDownCallback? onTapDown;
  final GestureTapUpCallback? onTertiaryTapUp;
  final MouseCursor cursor;
  final HitTestBehavior behavior;

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: widget.behavior,
        onTap: widget.onTap,
        onTapDown: widget.onTapDown,
        onSecondaryTap: widget.onSecondaryTap,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        onTertiaryTapUp: widget.onTertiaryTapUp,
        child: widget.builder(context, _hover),
      ),
    );
  }
}

/// Tiny key-cap-style chip used to render keyboard shortcut hints inline
/// next to buttons.
class KbdChip extends StatelessWidget {
  const KbdChip(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: Radii.brSm,
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        text,
        style: AppTheme.mono(size: 10, color: AppColors.textMuted),
      ),
    );
  }
}

/// Compact toolbar/dialog button with a hover state. The [primary] variant
/// fills with the amber accent; the default variant is a quiet outline.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
    this.danger = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final accent = danger ? AppColors.error : AppColors.accent;
    return Hoverable(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onTap: onPressed,
      builder: (context, hovering) {
        Color bg;
        Color fg;
        Color border;
        if (primary) {
          bg = hovering ? AppColors.accentHover : accent;
          fg = AppColors.bg;
          border = bg;
        } else {
          bg = hovering ? AppColors.surfaceHover : AppColors.surfaceAlt;
          fg = danger ? AppColors.error : AppColors.textPrimary;
          border = hovering ? AppColors.borderStrong : AppColors.border;
        }
        if (!enabled) {
          bg = AppColors.surfaceAlt;
          fg = AppColors.textMuted;
          border = AppColors.border;
        }
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Square icon-only button for toolbar affordances. `primary` colours the
/// icon in the accent (so it can stand in for a labelled primary button).
class IconAction extends StatelessWidget {
  const IconAction({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.primary = false,
    this.busy = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool primary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final button = Hoverable(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onTap: onPressed,
      builder: (context, hovering) {
        final Color iconColor;
        final Color hoverBg;
        if (primary) {
          iconColor = enabled
              ? (hovering ? AppColors.accentHover : AppColors.accent)
              : AppColors.textMuted;
          hoverBg = AppColors.accentSoft;
        } else {
          iconColor = enabled
              ? (hovering ? AppColors.textPrimary : AppColors.textSecondary)
              : AppColors.textMuted;
          hoverBg = AppColors.surfaceHover;
        }
        final glyph = busy
            ? SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: AppColors.accent,
                ),
              )
            : Icon(icon, size: 16, color: iconColor);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovering && enabled ? hoverBg : hoverBg.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(6),
          ),
          child: glyph,
        );
      },
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// Centered illustration + message used when a panel has nothing to show.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, size: 26, color: AppColors.textMuted),
            ),
            const SizedBox(height: Insets.lg),
            Text(
              title,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: Insets.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: Insets.xl), action!],
          ],
        ),
      ),
    );
  }
}
