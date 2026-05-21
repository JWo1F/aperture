import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Free-form timezone text input — accepts `UTC`, `+02:00`, `Europe/Berlin`, …
class TzInput extends StatefulWidget {
  const TzInput({super.key, required this.value, required this.onChange});

  final String value;
  final ValueChanged<String> onChange;

  @override
  State<TzInput> createState() => _TzInputState();
}

class _TzInputState extends State<TzInput> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(TzInput old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _c.text != widget.value) {
      _c.text = widget.value;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: Radii.brSm,
          ),
          child: Text(
            'TZ',
            style: AppTheme.mono(
              size: 10,
              color: AppColors.textMuted,
              weight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: _c,
            cursorColor: AppColors.accent,
            onChanged: widget.onChange,
            style: AppTheme.mono(size: 12),
            decoration: InputDecoration(
              isCollapsed: true,
              hintText: 'UTC / +02:00 / Europe/Berlin',
              hintStyle: AppTheme.mono(size: 11.5, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              border: OutlineInputBorder(
                borderRadius: Radii.brSm,
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: Radii.brSm,
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: Radii.brSm,
                borderSide: BorderSide(color: AppColors.accent),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
