import 'package:flutter/widgets.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:highlight/languages/json.dart' as lang_json;
import 'package:highlight/languages/pgsql.dart' as lang_pgsql;

import '../../../theme/app_theme.dart';
import '../../../theme/code_theme.dart';

/// `TextEditingController` that returns a highlight-tinted `TextSpan` tree
/// using a registered language grammar from the `highlight` package and the
/// shared [apertureCodeStyles] theme map.
class CodeEditorController extends TextEditingController {
  CodeEditorController({super.text, this.language = 'pgsql'}) {
    _registerLanguage(language);
  }

  /// Highlight language name (`pgsql`, `json`, …). Override and call
  /// [notifyListeners] to repaint with a new grammar.
  String language;

  String? _cachedText;
  String? _cachedLanguage;
  TextStyle? _cachedBase;
  AppBrightness? _cachedBrightness;
  TextSpan? _cachedSpan;

  /// Memoised on everything the result depends on.
  ///
  /// `highlight.parse` walks the whole document, and a single keystroke
  /// reaches this more than once: the editor measures line metrics, then
  /// keeps the caret visible, then re-anchors the suggestion popup, then
  /// the `TextField` paints. On a few-hundred-line script that was four
  /// full parses and two full layouts per character. The palette is part
  /// of the key because `apertureCodeStyles` is a live getter — the spans
  /// have to be rebuilt after a theme swap.
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final brightness = AppColors.brightness;
    if (_cachedSpan != null &&
        _cachedText == text &&
        _cachedLanguage == language &&
        _cachedBase == base &&
        _cachedBrightness == brightness) {
      return _cachedSpan!;
    }
    final span = text.isEmpty
        ? TextSpan(text: '', style: base)
        : TextSpan(
            style: base,
            children: highlightNodesToSpans(
              highlight.parse(text, language: language).nodes,
              base,
              apertureCodeStyles,
            ),
          );
    _cachedText = text;
    _cachedLanguage = language;
    _cachedBase = base;
    _cachedBrightness = brightness;
    _cachedSpan = span;
    return span;
  }
}

final _registeredLanguages = <String>{};

void _registerLanguage(String name) {
  if (!_registeredLanguages.add(name)) return;
  switch (name) {
    case 'pgsql':
      highlight.registerLanguage('pgsql', lang_pgsql.pgsql);
    case 'json':
      highlight.registerLanguage('json', lang_json.json);
  }
}
