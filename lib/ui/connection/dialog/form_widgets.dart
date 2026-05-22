import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/connection_config.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Inter caption rendered above a form control.
TextStyle get fieldLabelStyle => AppTheme.ui(
  size: 11,
  weight: FontWeight.w600,
  color: AppColors.textSecondary,
  letterSpacing: 0,
);

/// Muted helper line rendered below a form control.
TextStyle get fieldHintStyle => AppTheme.ui(
  size: 10.5,
  weight: FontWeight.w400,
  color: AppColors.textMuted,
  letterSpacing: 0,
);

/// Label above, control below, optional helper line — the standard form
/// row used throughout the connection dialog.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.hint,
  });

  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: fieldLabelStyle),
        const SizedBox(height: 7),
        child,
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(hint!, style: fieldHintStyle),
        ],
      ],
    );
  }
}

/// Faint hairline with a leading caption — separates form sections.
class DividerLabel extends StatelessWidget {
  const DividerLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: AppTheme.ui(
            size: 10,
            weight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: AppColors.hairline)),
      ],
    );
  }
}

/// Boxed text input with an Inter typeface and an accent focus ring. The
/// optional [trailing] sits inside the box (show-password toggle, the
/// SQLite browse actions).
class BoxedTextInput extends StatefulWidget {
  const BoxedTextInput({
    super.key,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.inputFormatters,
    this.autofocus = false,
    this.trailing,
  });

  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final Widget? trailing;

  @override
  State<BoxedTextInput> createState() => _BoxedTextInputState();
}

class _BoxedTextInputState extends State<BoxedTextInput> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: 36,
      padding: const EdgeInsets.only(left: 11, right: 6),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: Radii.brSm,
        border: Border.all(
          color: focused ? AppColors.accent : AppColors.border,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: AppColors.accentSoft,
                  blurRadius: 0,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              obscureText: widget.obscure,
              obscuringCharacter: '•',
              inputFormatters: widget.inputFormatters,
              cursorColor: AppColors.accent,
              cursorWidth: 1.5,
              cursorHeight: 14,
              style: AppTheme.ui(
                size: 12.5,
                weight: FontWeight.w500,
                color: AppColors.textPrimary,
                letterSpacing: 0,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: AppTheme.ui(
                  size: 12.5,
                  weight: FontWeight.w400,
                  color: AppColors.text4,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }
}

/// Read-only boxed control that opens a menu on tap — visually matches
/// [BoxedTextInput] so the SSL row sits flush with the text fields.
class BoxedSelect extends StatelessWidget {
  const BoxedSelect({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (_, hovering) => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: Radii.brSm,
          border: Border.all(
            color: hovering ? AppColors.borderStrong : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 9),
            Text(
              label,
              style: AppTheme.ui(
                size: 12.5,
                weight: FontWeight.w500,
                color: AppColors.textPrimary,
                letterSpacing: 0,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.unfold_more_rounded,
              size: 15,
              color: hovering ? AppColors.textSecondary : AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// Small icon-only affordance that lives inside a [BoxedTextInput] (the
/// show/hide-password eye).
class GhostIconButton extends StatelessWidget {
  const GhostIconButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (_, hovering) => Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hovering ? AppColors.surfaceHover : Colors.transparent,
          borderRadius: Radii.brSm,
        ),
        child: Icon(
          icon,
          size: 14,
          color: hovering ? AppColors.textPrimary : AppColors.textMuted,
        ),
      ),
    );
  }
}

/// Compact icon + label action used inside the SQLite file input.
class InlineAction extends StatelessWidget {
  const InlineAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (_, hovering) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: hovering ? AppColors.surfaceHover : Colors.transparent,
          borderRadius: Radii.brSm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: hovering ? AppColors.textPrimary : AppColors.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTheme.ui(
                size: 11.5,
                weight: FontWeight.w500,
                color: hovering ? AppColors.textPrimary : AppColors.textMuted,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width two-up selector for the database engine.
class EngineToggle extends StatelessWidget {
  const EngineToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final DbEngine value;
  final ValueChanged<DbEngine> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: Radii.brMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _segment(
              DbEngine.postgres,
              Icons.dns_rounded,
              'PostgreSQL',
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: _segment(
              DbEngine.sqlite,
              Icons.insert_drive_file_rounded,
              'SQLite',
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment(DbEngine engine, IconData icon, String label) {
    final selected = engine == value;
    return Hoverable(
      onTap: () => onChanged(engine),
      builder: (_, hovering) => AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentSoft
              : (hovering
                    ? AppColors.surfaceHover
                    : AppColors.surfaceHover.withValues(alpha: 0)),
          borderRadius: Radii.brSm,
          border: Border.all(
            color: selected
                ? AppColors.accentRing
                : AppColors.accentRing.withValues(alpha: 0),
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected
                  ? AppColors.accent
                  : (hovering
                        ? AppColors.textSecondary
                        : AppColors.textMuted),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTheme.ui(
                size: 12.5,
                weight: FontWeight.w600,
                letterSpacing: -0.1,
                color: selected
                    ? AppColors.accent
                    : (hovering
                          ? AppColors.textPrimary
                          : AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three-up segmented control for where a connection's password is stored.
class CredentialSourceToggle extends StatelessWidget {
  const CredentialSourceToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final CredentialSource value;
  final ValueChanged<CredentialSource> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: Radii.brSm,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(CredentialSource.plain, 'Plain'),
          _segment(CredentialSource.encrypted, 'Encrypted'),
          _segment(CredentialSource.onePassword, '1Password'),
        ],
      ),
    );
  }

  Widget _segment(CredentialSource source, String label) {
    final selected = source == value;
    return Hoverable(
      onTap: () => onChanged(source),
      builder: (_, hovering) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 9),
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent
              : AppColors.accent.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: AppTheme.ui(
            size: 10.5,
            weight: FontWeight.w600,
            letterSpacing: 0,
            color: selected
                ? Colors.white
                : (hovering ? AppColors.textPrimary : AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}

/// Round color chip used in the connection-color picker. Named to avoid a
/// clash with Flutter's own `ColorSwatch`.
class ColorSwatchButton extends StatelessWidget {
  const ColorSwatchButton({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (_, hovering) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: color.withValues(
            alpha: selected ? 1 : (hovering ? 0.9 : 0.8),
          ),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? AppColors.textPrimary
                : color.withValues(alpha: 0.0),
            width: 2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.45),
                    blurRadius: 9,
                    spreadRadius: -1,
                  ),
                ]
              : null,
        ),
        child: selected
            ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
            : null,
      ),
    );
  }
}

/// Pill-shaped on/off switch.
class PillToggle extends StatelessWidget {
  const PillToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: () => onChanged(!value),
      builder: (_, hovering) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          width: 32,
          height: 18,
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            color: value
                ? AppColors.accent
                : (hovering ? AppColors.surfaceHover : AppColors.surfaceAlt),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: value ? AppColors.accent : AppColors.borderStrong,
            ),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: value ? Colors.white : AppColors.textMuted,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}
