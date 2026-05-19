import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Compact toolbar/dialog button with a hover state. The [primary] variant
/// fills with the amber accent; the default variant is a quiet outline.
class AppButton extends StatefulWidget {
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
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final accent = widget.danger ? AppColors.error : AppColors.accent;

    Color bg;
    Color fg;
    Color border;
    if (widget.primary) {
      bg = _hover ? AppColors.accentHover : accent;
      fg = AppColors.bg;
      border = bg;
    } else {
      bg = _hover ? AppColors.surfaceHover : AppColors.surfaceAlt;
      fg = widget.danger ? AppColors.error : AppColors.textPrimary;
      border = _hover ? AppColors.borderStrong : AppColors.border;
    }
    if (!enabled) {
      bg = AppColors.surfaceAlt;
      fg = AppColors.textMuted;
      border = AppColors.border;
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
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
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 14, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Square icon-only button for toolbar affordances. `primary` colours the
/// icon in the accent (so it can stand in for a labelled primary button).
class IconAction extends StatefulWidget {
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
  State<IconAction> createState() => _IconActionState();
}

class _IconActionState extends State<IconAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;

    Color iconColor;
    Color hoverBg;
    if (widget.primary) {
      iconColor = enabled
          ? (_hover ? AppColors.accentHover : AppColors.accent)
          : AppColors.textMuted;
      hoverBg = AppColors.accentSoft;
    } else {
      iconColor = enabled
          ? (_hover ? AppColors.textPrimary : AppColors.textSecondary)
          : AppColors.textMuted;
      hoverBg = AppColors.surfaceHover;
    }

    final Widget glyph = widget.busy
        ? const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: AppColors.accent,
            ),
          )
        : Icon(widget.icon, size: 16, color: iconColor);

    final button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover && enabled ? hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: glyph,
        ),
      ),
    );

    if (widget.tooltip == null) return button;
    return Tooltip(message: widget.tooltip!, child: button);
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
              style: const TextStyle(
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
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: Insets.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
