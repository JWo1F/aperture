import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show Node;

import 'app_theme.dart';

/// Aperture-tuned highlight theme. Maps `highlight` token class names to
/// [TextStyle]s. Shared by `flutter_highlight`'s `HighlightView`,
/// `flutter_code_editor`'s `CodeTheme`, and our custom controllers.
final Map<String, TextStyle> apertureCodeStyles = {
  'root': const TextStyle(
    color: AppColors.textPrimary,
    backgroundColor: AppColors.bg,
  ),
  'keyword': const TextStyle(
    color: AppColors.sqlKeyword,
    fontWeight: FontWeight.w500,
  ),
  'built_in': const TextStyle(color: AppColors.sqlFunction),
  'type': const TextStyle(color: AppColors.sqlKeyword),
  'literal': const TextStyle(color: AppColors.sqlNumber),
  'number': const TextStyle(color: AppColors.sqlNumber),
  'string': const TextStyle(color: AppColors.sqlString),
  'symbol': const TextStyle(color: AppColors.sqlString),
  'comment': const TextStyle(
    color: AppColors.sqlComment,
    fontStyle: FontStyle.italic,
  ),
  'meta': const TextStyle(color: AppColors.sqlComment),
  'operator': const TextStyle(color: AppColors.textSecondary),
  'punctuation': const TextStyle(color: AppColors.textSecondary),
  // pgsql-specific token kinds that show up in real schemas
  'attr': const TextStyle(color: AppColors.sqlIdentifier),
  'name': const TextStyle(color: AppColors.sqlIdentifier),
  'function': const TextStyle(color: AppColors.sqlFunction),
};

/// Walks a `highlight` parse tree and returns the matching [TextSpan] tree.
/// Theme styles are merged on top of [base] so the caller's font choice
/// (size / family) is preserved while colours come from [theme].
List<InlineSpan> highlightNodesToSpans(
  List<Node>? nodes,
  TextStyle base,
  Map<String, TextStyle> theme,
) {
  if (nodes == null) return const [];
  final out = <InlineSpan>[];
  for (final node in nodes) {
    final classStyle =
        node.className == null ? null : theme[node.className!];
    if (node.value != null) {
      out.add(TextSpan(
        text: node.value,
        style: classStyle == null ? base : base.merge(classStyle),
      ));
    } else if (node.children != null) {
      final inner = classStyle == null ? base : base.merge(classStyle);
      out.add(TextSpan(
        children: highlightNodesToSpans(node.children, inner, theme),
      ));
    }
  }
  return out;
}
