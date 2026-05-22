import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show Node, highlight;
import 'package:highlight/languages/json.dart' as lang_json;

import 'app_theme.dart';

/// Aperture-tuned highlight theme. Maps `highlight` token class names to
/// [TextStyle]s. Shared by `flutter_highlight`'s `HighlightView`,
/// `flutter_code_editor`'s `CodeTheme`, and our custom controllers.
///
/// Rebuilt on each access so palette swaps (dark ⇄ light) take effect on
/// the next paint without threading a theme object through every consumer.
Map<String, TextStyle> get apertureCodeStyles => {
  'root': TextStyle(
    color: AppColors.textPrimary,
    backgroundColor: AppColors.bg,
  ),
  'keyword': TextStyle(
    color: AppColors.sqlKeyword,
    fontWeight: FontWeight.w500,
  ),
  'built_in': TextStyle(color: AppColors.sqlFunction),
  'type': TextStyle(color: AppColors.sqlKeyword),
  'literal': TextStyle(color: AppColors.sqlNumber),
  'number': TextStyle(color: AppColors.sqlNumber),
  'string': TextStyle(color: AppColors.sqlString),
  'symbol': TextStyle(color: AppColors.sqlString),
  'comment': TextStyle(
    color: AppColors.sqlComment,
    fontStyle: FontStyle.italic,
  ),
  'meta': TextStyle(color: AppColors.sqlComment),
  'operator': TextStyle(color: AppColors.sqlOperator),
  'punctuation': TextStyle(color: AppColors.sqlOperator),
  'attr': TextStyle(color: AppColors.sqlIdentifier),
  'name': TextStyle(color: AppColors.sqlIdentifier),
  'function': TextStyle(color: AppColors.sqlFunction),
};

/// Tokenises a JSON string into coloured spans using the shared
/// [apertureCodeStyles] palette — same look as the cell-picker's JSON
/// editor and the SQL editor. Used by the table grid to render Map/List
/// cell values where dropping in a full `CodeEditor` isn't viable.
///
/// Callers length-cap [source] themselves — the grid cell and its hover
/// expansion each hand in an already-truncated string — so this highlights
/// whatever it is given in full.
List<InlineSpan> jsonSpans(String source, TextStyle base) {
  if (source.isEmpty) return const [];
  _ensureJsonRegistered();
  final parsed = highlight.parse(source, language: 'json');
  // JSON's structural punctuation — { } [ ] : , — carries no highlight class,
  // so it falls through to `base`. Pin that fallback to the operator tone (a
  // live palette colour) so braces and colons read as a clean, theme-correct
  // grey rather than inheriting whatever colour `base` froze with. The classed
  // tokens — keys, strings, numbers — override the colour anyway.
  final punctBase = base.copyWith(color: AppColors.sqlOperator);
  return highlightNodesToSpans(parsed.nodes, punctBase, apertureCodeStyles);
}

bool _jsonRegistered = false;
void _ensureJsonRegistered() {
  if (_jsonRegistered) return;
  highlight.registerLanguage('json', lang_json.json);
  _jsonRegistered = true;
}

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
    final classStyle = node.className == null ? null : theme[node.className!];
    if (node.value != null) {
      out.add(
        TextSpan(
          text: node.value,
          style: classStyle == null ? base : base.merge(classStyle),
        ),
      );
    } else if (node.children != null) {
      final inner = classStyle == null ? base : base.merge(classStyle);
      out.add(
        TextSpan(children: highlightNodesToSpans(node.children, inner, theme)),
      );
    }
  }
  return out;
}
