import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import '../../widgets/code_view.dart';

/// Multi-line values in `re_editor`, which lays out and paints only the
/// lines in view — a large JSON document stays responsive to type in,
/// where a `TextField` re-lays the whole document out on every keystroke.
class TextBody extends StatelessWidget {
  const TextBody({
    super.key,
    required this.controller,
    required this.focus,
    required this.isJson,
    required this.onChanged,
    this.error,
  });

  final CodeLineEditingController controller;
  final FocusNode focus;
  final bool isJson;
  final VoidCallback onChanged;
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
            wordWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            onChanged: (_) => onChanged(),
            shortcutsActivatorsBuilder: const AppCodeShortcuts(),
            scrollbarBuilder: codeScrollbar,
            verticalScrollbarWidth: 10,
            style: codeEditorStyle(
              language: isJson ? CodeLanguage.json : CodeLanguage.plain,
              background: AppColors.surface,
            ),
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
