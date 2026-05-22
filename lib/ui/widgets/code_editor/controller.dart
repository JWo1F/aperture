import 'package:flutter/widgets.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:highlight/languages/json.dart' as lang_json;
import 'package:highlight/languages/pgsql.dart' as lang_pgsql;

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

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    if (text.isEmpty) return TextSpan(text: '', style: base);
    final parsed = highlight.parse(text, language: language);
    return TextSpan(
      style: base,
      children: highlightNodesToSpans(parsed.nodes, base, apertureCodeStyles),
    );
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
