import 'package:flutter/material.dart';

import 'json_spans.dart';

/// JSON-highlighted text controller — defers to [jsonSpans] so the inline
/// renderer in the table grid and the editable picker share one tokenizer
/// and one colour palette. Live-tokenizes on each keystroke; tolerant of
/// incomplete input because [jsonSpans] is single-pass and never throws.
class JsonHighlightController extends TextEditingController {
  JsonHighlightController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    if (text.isEmpty) return TextSpan(text: '', style: base);
    return TextSpan(style: base, children: jsonSpans(text, base));
  }
}
