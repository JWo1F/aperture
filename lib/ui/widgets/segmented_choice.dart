import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'common.dart';

/// Compact segmented control. The selection moves instantly — no
/// cross-fade between segments.
class SegmentedChoice<T> extends StatelessWidget {
  const SegmentedChoice({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

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
          for (final (option, label) in options) _segment(option, label),
        ],
      ),
    );
  }

  Widget _segment(T option, String label) {
    final selected = option == value;
    return Hoverable(
      onTap: () => onChanged(option),
      builder: (_, hovering) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9),
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent
              : hovering
              ? AppColors.surfaceHover
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
