import 'package:flutter/widgets.dart';
import 'package:highlight/highlight.dart' show Node, highlight;
import 'package:highlight/languages/json.dart';

import '../../theme/app_theme.dart';

/// Tokenises a JSON string into coloured [TextSpan]s using the `highlight`
/// package's `json` grammar (shared with our SQL highlighter) plus the dbv
/// palette. Single source of truth for JSON colour in the table grid and
/// the cell-picker editor.
List<InlineSpan> jsonSpans(String source, TextStyle base) {
  if (source.isEmpty) return const [];
  _registerOnce();
  final parsed = highlight.parse(source, language: 'json');
  return _walk(parsed.nodes, base);
}

bool _registered = false;

void _registerOnce() {
  if (_registered) return;
  highlight.registerLanguage('json', json);
  _registered = true;
}

TextStyle? _styleFor(String? className, String? value, TextStyle base) {
  switch (className) {
    case 'attr':
      return base.copyWith(color: AppColors.sqlKeyword);
    case 'string':
      return base.copyWith(color: AppColors.sqlString);
    case 'number':
      return base.copyWith(color: AppColors.sqlNumber);
    case 'literal':
      // Treat `null` as muted (it's the absence of a value), `true`/`false`
      // as a function-tinted keyword like in the grid renderer.
      if (value == 'null') return base.copyWith(color: AppColors.textMuted);
      return base.copyWith(color: AppColors.sqlFunction);
    case 'punctuation':
      return base.copyWith(color: AppColors.textSecondary);
    default:
      return null;
  }
}

List<InlineSpan> _walk(List<Node>? nodes, TextStyle base) {
  if (nodes == null) return const [];
  final out = <InlineSpan>[];
  for (final node in nodes) {
    final classStyle = _styleFor(node.className, node.value, base);
    if (node.value != null) {
      out.add(TextSpan(text: node.value, style: classStyle ?? base));
    } else if (node.children != null) {
      // Children inherit the parent's class style as their `base`, so a
      // nested string literal inside a `string` node still picks up the
      // right colour even when the inner node has no className.
      final inner = classStyle ?? base;
      out.add(TextSpan(children: _walk(node.children, inner)));
    }
  }
  return out;
}
