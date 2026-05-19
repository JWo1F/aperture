import 'package:flutter/material.dart';

import 'sql_spans.dart';

/// SQL-highlighted text controller for single-line filter fields. Delegates
/// tokenisation to [sqlSpans] so the preview modal and the inline fields
/// share one implementation.
class SqlHighlightController extends TextEditingController {
  SqlHighlightController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    return TextSpan(style: base, children: sqlSpans(text, base));
  }
}
