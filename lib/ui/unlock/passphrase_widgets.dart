import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/hugeicons.dart';
import '../connection/dialog/form_widgets.dart';
import '../widgets/common.dart';

/// Obscured text input with a show/hide toggle.
class PassphraseField extends StatefulWidget {
  const PassphraseField({
    super.key,
    required this.controller,
    required this.hint,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PassphraseField> createState() => _PassphraseFieldState();
}

class _PassphraseFieldState extends State<PassphraseField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return BoxedTextInput(
      controller: widget.controller,
      hint: widget.hint,
      obscure: !_visible,
      autofocus: widget.autofocus,
      onSubmitted: widget.onSubmitted,
      trailing: GhostIconButton(
        icon: _visible ? Hgi.viewOff : Hgi.view,
        onTap: () => setState(() => _visible = !_visible),
      ),
    );
  }
}

/// "Remember in Keychain" switch row.
class RememberToggle extends StatelessWidget {
  const RememberToggle({
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
      builder: (context, hovering) => Row(
        children: [
          Icon(
            Hgi.key01,
            size: 14,
            color: value ? AppColors.accent : AppColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Remember in Keychain',
                  style: AppTheme.ui(
                    size: 12.5,
                    weight: FontWeight.w500,
                    color: AppColors.textPrimary,
                    letterSpacing: 0,
                  ),
                ),
                Text(
                  'Unlock automatically while you are logged in to macOS.',
                  style: fieldHintStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PillToggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
