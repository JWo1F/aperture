import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/hugeicons.dart';

/// Compact 24 px search box with a clear button, for filtering a list in
/// place.
class FilterField extends StatefulWidget {
  const FilterField({super.key, required this.controller, required this.hint});

  final TextEditingController controller;
  final String hint;

  @override
  State<FilterField> createState() => _FilterFieldState();
}

class _FilterFieldState extends State<FilterField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(FilterField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    final hasText = widget.controller.text.isNotEmpty;
    final textStyle = AppTheme.ui(
      size: 12,
      color: AppColors.textPrimary,
      weight: FontWeight.w400,
      letterSpacing: 0,
    );
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: focused ? AppColors.bg : AppColors.surfaceAlt,
        borderRadius: Radii.brSm,
        border: Border.all(
          color: focused ? AppColors.accentRing : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(Hgi.search01, size: 12, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              cursorColor: AppColors.accent,
              cursorWidth: 1.4,
              cursorHeight: 13,
              style: textStyle,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: textStyle.copyWith(color: AppColors.textMuted),
              ),
            ),
          ),
          if (hasText)
            GestureDetector(
              onTap: widget.controller.clear,
              child: Icon(Hgi.cancel01, size: 11, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}
