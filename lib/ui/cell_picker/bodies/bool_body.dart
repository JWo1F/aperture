import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../widgets/common.dart';

class BoolBody extends StatelessWidget {
  const BoolBody({
    super.key,
    required this.value,
    required this.onChange,
    required this.onNull,
  });

  final bool? value;
  final ValueChanged<bool> onChange;
  final VoidCallback onNull;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          _option(
            label: 'true',
            icon: Icons.check,
            selected: value == true,
            onTap: () => onChange(true),
          ),
          const SizedBox(width: 4),
          _option(
            label: 'false',
            icon: Icons.close,
            selected: value == false,
            onTap: () => onChange(false),
          ),
          const SizedBox(width: 4),
          _option(
            label: 'NULL',
            icon: Icons.horizontal_rule,
            selected: value == null,
            onTap: onNull,
          ),
        ],
      ),
    );
  }

  Widget _option({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Hoverable(
        onTap: onTap,
        builder: (_, hover) => Container(
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accentSoft
                : (hover ? AppColors.surfaceHover : Colors.transparent),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 10,
                color: selected ? AppColors.textPrimary : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTheme.mono(
                  size: 11,
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
