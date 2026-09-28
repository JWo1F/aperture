import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import '../../widgets/common.dart';
import '../kinds.dart';

/// Right-aligned mono input with a ±1 stepper on its trailing edge.
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
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Container(
        height: 30,
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: Radii.brSm,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focus,
                textAlign: TextAlign.right,
                cursorColor: AppColors.accent,
                inputFormatters: [widget.intOnly ? intFilter : numberFilter],
                style: AppTheme.mono(
                  size: 12.5,
                  color: AppColors.textPrimary,
                ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8),
                ),
                onChanged: (_) => widget.onChanged(),
              ),
            ),
            Column(
              children: [
                _StepperBtn(icon: Hgi.arrowUp01, onTap: () => _bump(1)),
                _StepperBtn(icon: Hgi.arrowDown01, onTap: () => _bump(-1)),
              ],
            ),
          ],
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
        width: 20,
        height: 14,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 11,
          color: hovering ? AppColors.textPrimary : AppColors.text4,
        ),
      ),
    );
  }
}
