import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/pgsql.dart';

import '../../theme/app_theme.dart';
import '../../theme/code_theme.dart';

/// Shared chrome for the app's `re_editor` surfaces — the SQL editor and
/// the cell picker's multi-line body — so both read and behave alike.

enum CodeLanguage { plain, json, sql }

/// The editor's text, selection and caret colours plus highlighting for
/// [language] through [apertureCodeStyles]. [background] may be
/// transparent when something is painted beneath the text.
CodeEditorStyle codeEditorStyle({
  required CodeLanguage language,
  required Color background,
  double fontSize = 12.5,
}) => CodeEditorStyle(
  fontFamily: AppTheme.monoFamily,
  fontSize: fontSize,
  fontHeight: 1.45,
  textColor: AppColors.textPrimary,
  hintTextColor: AppColors.text4,
  backgroundColor: background,
  selectionColor: AppColors.accentSoft,
  cursorColor: AppColors.accent,
  cursorLineColor: AppColors.surface.withValues(alpha: 0),
  codeTheme: switch (language) {
    CodeLanguage.plain => null,
    CodeLanguage.json => CodeHighlightTheme(
      languages: {'json': CodeHighlightThemeMode(mode: langJson)},
      theme: apertureCodeStyles,
    ),
    CodeLanguage.sql => CodeHighlightTheme(
      languages: {'pgsql': CodeHighlightThemeMode(mode: langPgsql)},
      theme: apertureCodeStyles,
    ),
  },
);

Widget codeScrollbar(
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

/// The package's macOS keys, minus the ones the app owns: ⌘↵ and ⇧⌘↵ run
/// or save, and Esc closes the picker — the package would otherwise take
/// them as a newline and a selection collapse. Find, replace and save are
/// dropped too; there is no find panel, and ⌘S has no meaning here.
class AppCodeShortcuts extends CodeShortcutsActivatorsBuilder {
  const AppCodeShortcuts();

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
