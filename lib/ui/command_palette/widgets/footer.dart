import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import 'key_cap.dart';

class PaletteFooter extends StatelessWidget {
  const PaletteFooter({super.key, required this.query, required this.count});

  final String query;
  final int count;

  @override
  Widget build(BuildContext context) {
    final left = query.isEmpty
        ? 'Quick access'
        : '$count match${count == 1 ? '' : 'es'}';
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Text(
            left,
            style: AppTheme.mono(size: 10.5, color: AppColors.textMuted),
          ),
          const Spacer(),
          _Hint(keys: const ['↑', '↓'], label: 'Navigate'),
          const SizedBox(width: 12),
          _Hint(keys: const ['↵'], label: 'Open'),
          const SizedBox(width: 12),
          _Hint(keys: const ['esc'], label: 'Close'),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.keys, required this.label});

  final List<String> keys;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final k in keys) ...[
          KeyCap(label: k),
          const SizedBox(width: 3),
        ],
        Text(
          label,
          style: AppTheme.ui(size: 10.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}
