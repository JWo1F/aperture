import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:highlight/languages/json.dart';

import '../../theme/code_theme.dart';

/// JSON-highlighted text controller — uses the `highlight` package's json
/// grammar so keys, strings, numbers, booleans and null are coloured live
/// as the user types.
class JsonHighlightController extends TextEditingController {
  JsonHighlightController({super.text}) {
    _registered ??= () {
      highlight.registerLanguage('json', json);
      return true;
    }();
  }

  static bool? _registered;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    if (text.isEmpty) return TextSpan(text: '', style: base);
    final parsed = highlight.parse(text, language: 'json');
    return TextSpan(
      style: base,
      children: highlightNodesToSpans(parsed.nodes, base, apertureCodeStyles),
    );
  }
}
