import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import '../../widgets/common.dart';
import '../kinds.dart';

/// Right-aligned mono input + vertical stepper for the number kind.
/// Matches the design's `.num-field` / `.num-steppers` layout.
class NumberBody extends StatefulWidget {
  const NumberBody({
    super.key,
    required this.controller,
    required this.focus,
    required this.intOnly,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool intOnly;
  final VoidCallback onChanged;

  @override
  State<NumberBody> createState() => _NumberBodyState();
}

class _NumberBodyState extends State<NumberBody> {
  void _bump(int delta) {
    final raw = widget.controller.text.trim();
    final current = num.tryParse(raw.isEmpty ? '0' : raw) ?? num.parse('0');
    final next = widget.intOnly ? (current + delta).round() : current + delta;
    widget.controller.text = next.toString();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgDeep,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: AppColors.border),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focus,
                  textAlign: TextAlign.right,
                  cursorColor: AppColors.accent,
                  inputFormatters: [
                    widget.intOnly ? intFilter : numberFilter,
                  ],
                  style: AppTheme.mono(size: 12, color: AppColors.textPrimary)
                      .copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
              Container(width: 1, color: AppColors.border),
              Column(
                children: [
                  _StepperBtn(
                    icon: Hgi.arrowUp01,
                    onTap: () => _bump(1),
                  ),
                  Container(width: 22, height: 1, color: AppColors.border),
                  _StepperBtn(
                    icon: Hgi.arrowDown01,
                    onTap: () => _bump(-1),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepperBtn extends StatelessWidget {
  const _StepperBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => Container(
        width: 22,
        height: 18,
        alignment: Alignment.center,
        color: hovering ? AppColors.surfaceHover : Colors.transparent,
        child: Icon(
          icon,
          size: 14,
          color: hovering ? AppColors.textPrimary : AppColors.textMuted,
        ),
      ),
    );
  }
}
