import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// true / false / NULL as one segmented strip. NULL commits at once, the
/// same as the footer's NULL on other kinds, so the footer leaves it out
/// for booleans.
class BoolBody extends StatelessWidget {
  const BoolBody({
    super.key,
    required this.value,
    required this.canBeNull,
    required this.onChange,
    required this.onNull,
  });

  final bool? value;
  final bool canBeNull;
  final ValueChanged<bool> onChange;
  final VoidCallback onNull;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Container(
        height: 28,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: Radii.brSm,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            _segment('true', value == true, () => onChange(true)),
            _segment('false', value == false, () => onChange(false)),
            _segment('NULL', value == null, canBeNull ? onNull : null),
          ],
        ),
      ),
    );
  }

  Widget _segment(String label, bool selected, VoidCallback? onTap) {
    final enabled = onTap != null;
    return Expanded(
      child: Hoverable(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onTap: onTap,
        builder: (_, hovering) => Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent
                : (hovering && enabled
                      ? AppColors.surfaceHover
                      : AppColors.surfaceHover.withValues(alpha: 0)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: AppTheme.mono(
              size: 11.5,
              weight: FontWeight.w500,
              color: selected
                  ? Colors.white
                  : !enabled
                  ? AppColors.text4
                  : (hovering
                        ? AppColors.textPrimary
                        : AppColors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}
