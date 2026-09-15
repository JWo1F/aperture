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
    return Container(
      color: AppColors.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: CodeEditor(
              controller: controller,
              focusNode: focus,
              singleLine: !multiline,
              fontSize: 12,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              inputFormatters: inputFormatters,
              onChanged: (_) => onChanged(),
            ),
          ),
          if (error != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.dangerSoft,
                border: Border(top: BorderSide(color: AppColors.error)),
              ),
              child: Row(
                children: [
                  Icon(Hgi.alertCircle, size: 13, color: AppColors.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.mono(size: 11, color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
