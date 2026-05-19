import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';

/// Lightweight SQL tokeniser shared by the inline field controller and any
/// place that wants to render a SQL fragment as coloured spans (preview
/// modals, etc.). Works on single- or multi-line input.
List<InlineSpan> sqlSpans(String source, TextStyle base) {
  if (source.isEmpty) return const [];

  final spans = <InlineSpan>[];
  for (final match in _token.allMatches(source)) {
    final piece = match.group(0)!;
    final color = _colorFor(piece);
    spans.add(TextSpan(
      text: piece,
      style: color == null ? base : base.copyWith(color: color),
    ));
  }
  return spans;
}

/// SQL keywords coloured as `sqlKeyword`. Includes both DML/DDL and the
/// common Postgres-specific words our generated UPDATE/SELECT clauses use.
const _keywords = {
  'SELECT', 'FROM', 'WHERE', 'AND', 'OR', 'NOT', 'IN', 'IS', 'NULL',
  'TRUE', 'FALSE', 'ORDER', 'BY', 'ASC', 'DESC', 'LIMIT', 'OFFSET',
  'GROUP', 'HAVING', 'JOIN', 'INNER', 'LEFT', 'RIGHT', 'FULL', 'OUTER',
  'ON', 'AS', 'LIKE', 'ILIKE', 'BETWEEN', 'EXISTS', 'UNION', 'ALL',
  'INSERT', 'UPDATE', 'DELETE', 'SET', 'VALUES', 'RETURNING',
  'CASE', 'WHEN', 'THEN', 'ELSE', 'END', 'INTO', 'DISTINCT', 'WITH',
  'CAST', 'COALESCE', 'NULLIF', 'DEFAULT', 'CTID',
};

final RegExp _token = RegExp(
  r"--[^\n]*"
  r"|'(?:[^']|'')*'"
  r'|"(?:[^"]|"")*"'
  r"|\b\d+(?:\.\d+)?\b"
  r"|[A-Za-z_][A-Za-z0-9_]*"
  r"|[^A-Za-z0-9_\s]+"
  r"|\s+",
);

Color? _colorFor(String token) {
  final first = token.codeUnitAt(0);
  if (first == 0x2D && token.startsWith('--')) return AppColors.sqlComment;
  if (first == 0x27) return AppColors.sqlString;
  if (first == 0x22) return AppColors.sqlIdentifier;
  if (first >= 0x30 && first <= 0x39) return AppColors.sqlNumber;
  if ((first >= 0x41 && first <= 0x5A) ||
      (first >= 0x61 && first <= 0x7A) ||
      first == 0x5F) {
    if (_keywords.contains(token.toUpperCase())) return AppColors.sqlKeyword;
    return null;
  }
  return AppColors.textSecondary;
}
