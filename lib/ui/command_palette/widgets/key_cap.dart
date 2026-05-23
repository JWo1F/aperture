import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

class KeyCap extends StatelessWidget {
  const KeyCap({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 18,
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        // height: 1.0 collapses the mono font's 1.4 line box so the glyph
        // sits centred in the 18px cap instead of riding its top edge.
        style: AppTheme.mono(
          size: 10,
          color: AppColors.textMuted,
          weight: FontWeight.w500,
        ).copyWith(height: 1.0),
      ),
    );
  }
}
