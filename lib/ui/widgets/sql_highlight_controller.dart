import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:highlight/languages/pgsql.dart';

import '../../theme/code_theme.dart';

/// SQL-highlighted text controller for single-line filter fields. Uses the
/// `highlight` package's `pgsql` grammar so the full Postgres vocabulary
/// (CREATE, INDEX, FOREIGN KEY, etc.) is tokenised correctly without us
/// maintaining a keyword list.
class SqlHighlightController extends TextEditingController {
  SqlHighlightController({super.text}) {
    _registered ??= () {
      highlight.registerLanguage('pgsql', pgsql);
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
    final parsed = highlight.parse(text, language: 'pgsql');
    return TextSpan(
      style: base,
      children: highlightNodesToSpans(parsed.nodes, base, apertureCodeStyles),
    );
  }
}
