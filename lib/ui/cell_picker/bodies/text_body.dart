import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import '../../widgets/code_editor.dart';

class TextBody extends StatelessWidget {
  const TextBody({
    super.key,
    required this.controller,
    required this.focus,
    required this.multiline,
    required this.onChanged,
    this.inputFormatters,
    this.error,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool multiline;
  final VoidCallback onChanged;
  final List<TextInputFormatter>? inputFormatters;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CodeEditor(
            controller: controller,
            focusNode: focus,
            singleLine: !multiline,
            fontSize: 12.5,
            background: AppColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            inputFormatters: inputFormatters,
            onChanged: (_) => onChanged(),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            child: Row(
              children: [
                Icon(Hgi.alertCircle, size: 12, color: AppColors.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.ui(size: 11, color: AppColors.error),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
