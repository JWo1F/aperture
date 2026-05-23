import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../item_model.dart';

class PaletteGroupHeader extends StatelessWidget {
  const PaletteGroupHeader({super.key, required this.kind, required this.count});

  final PaletteKind kind;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 5),
      child: Row(
        children: [
          Text(kind.section.toUpperCase(), style: AppTheme.eyebrow()),
          const SizedBox(width: 7),
          Text(
            '$count',
            style: AppTheme.eyebrow(color: AppColors.text4),
          ),
          const SizedBox(width: 9),
          Expanded(child: Container(height: 1, color: AppColors.hairline)),
        ],
      ),
    );
  }
}
