import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/json.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/code_theme.dart';
import '../../../theme/hugeicons.dart';

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
            shortcutsActivatorsBuilder: const _PickerShortcuts(),
            scrollbarBuilder: _scrollbar,
            verticalScrollbarWidth: 10,
            style: CodeEditorStyle(
              fontFamily: AppTheme.monoFamily,
              fontSize: 12.5,
              fontHeight: 1.45,
              textColor: AppColors.textPrimary,
              hintTextColor: AppColors.text4,
              backgroundColor: AppColors.surface,
              selectionColor: AppColors.accentSoft,
              cursorColor: AppColors.accent,
              cursorLineColor: AppColors.surface.withValues(alpha: 0),
              codeTheme: isJson
                  ? CodeHighlightTheme(
                      languages: {
                        'json': CodeHighlightThemeMode(mode: langJson),
                      },
                      theme: apertureCodeStyles,
                    )
                  : null,
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

  static Widget _scrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => RawScrollbar(
    controller: details.controller,
    thumbColor: AppColors.borderStrong,
    thickness: 6,
    radius: const Radius.circular(3),
    padding: const EdgeInsets.all(2),
    child: child,
  );
}

/// The package's macOS keys, minus the ones the picker owns: ⌘↵ saves and
/// Esc closes, and the package would otherwise take them as a newline and
/// a find-panel dismiss. Find and replace are dropped too — there is no
/// find panel to open.
class _PickerShortcuts extends CodeShortcutsActivatorsBuilder {
  const _PickerShortcuts();

  static const _defaults = DefaultCodeShortcutsActivatorsBuilder();

  @override
  List<ShortcutActivator>? build(CodeShortcutType type) => switch (type) {
    CodeShortcutType.esc ||
    CodeShortcutType.find ||
    CodeShortcutType.replace ||
    CodeShortcutType.findToggleMatchCase ||
    CodeShortcutType.findToggleRegex ||
    CodeShortcutType.save => null,
    CodeShortcutType.newLine => const [
      SingleActivator(LogicalKeyboardKey.enter),
      SingleActivator(LogicalKeyboardKey.enter, shift: true),
      SingleActivator(LogicalKeyboardKey.numpadEnter),
      SingleActivator(LogicalKeyboardKey.numpadEnter, shift: true),
    ],
    _ => _defaults.build(type),
  };
}
