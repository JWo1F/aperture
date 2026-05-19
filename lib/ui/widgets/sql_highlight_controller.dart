import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Lightweight inline SQL tokeniser for single-line fields (WHERE, ORDER BY).
///
/// For the multi-line query editor we use `flutter_code_editor` instead; this
/// controller exists so the small filter inputs feel like editor fields
/// without paying for the full code-field stack.
class SqlHighlightController extends TextEditingController {
  SqlHighlightController({super.text});

  static final _token = RegExp(
    r"--[^\n]*"
    r"|'(?:[^']|'')*'"
    r'|"(?:[^"]|"")*"'
    r"|\b\d+(?:\.\d+)?\b"
    r"|[A-Za-z_][A-Za-z0-9_]*"
    r"|[^A-Za-z0-9_\s]+"
    r"|\s+",
  );

  static const _keywords = {
    'SELECT', 'FROM', 'WHERE', 'AND', 'OR', 'NOT', 'IN', 'IS', 'NULL',
    'TRUE', 'FALSE', 'ORDER', 'BY', 'ASC', 'DESC', 'LIMIT', 'OFFSET',
    'GROUP', 'HAVING', 'JOIN', 'INNER', 'LEFT', 'RIGHT', 'FULL', 'OUTER',
    'ON', 'AS', 'LIKE', 'ILIKE', 'BETWEEN', 'EXISTS', 'UNION', 'ALL',
    'INSERT', 'UPDATE', 'DELETE', 'SET', 'VALUES', 'RETURNING',
    'CASE', 'WHEN', 'THEN', 'ELSE', 'END', 'INTO', 'DISTINCT', 'WITH',
    'CAST', 'COALESCE', 'NULLIF',
  };

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final source = text;
    if (source.isEmpty) return TextSpan(text: '', style: style);

    final base = style ?? const TextStyle();
    final children = <TextSpan>[];

    for (final match in _token.allMatches(source)) {
      final piece = match.group(0)!;
      children.add(TextSpan(text: piece, style: base.copyWith(color: _colorFor(piece))));
    }

    return TextSpan(style: base, children: children);
  }

  Color? _colorFor(String token) {
    final first = token.codeUnitAt(0);
    if (first == 0x2D && token.startsWith('--')) return AppColors.sqlComment;
    if (first == 0x27) return AppColors.sqlString; // single quote
    if (first == 0x22) return AppColors.textPrimary; // "ident"
    if (first >= 0x30 && first <= 0x39) return AppColors.sqlNumber;
    if ((first >= 0x41 && first <= 0x5A) ||
        (first >= 0x61 && first <= 0x7A) ||
        first == 0x5F) {
      if (_keywords.contains(token.toUpperCase())) return AppColors.sqlKeyword;
      return null;
    }
    return AppColors.textSecondary;
  }
}
