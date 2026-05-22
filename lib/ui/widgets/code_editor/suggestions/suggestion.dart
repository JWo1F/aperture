import 'dart:async';

import 'package:flutter/widgets.dart';

/// A single suggestion shown by the autocomplete popup. [kind] and
/// [matchBoost] are consumed by the ranker in `sql_complete.dart`; the
/// editor itself only reads label/insert/detail/icon/[chainNext].
class CodeSuggestion {
  const CodeSuggestion({
    required this.label,
    required this.insertText,
    this.detail,
    this.icon,
    this.kind = SuggestionKind.keyword,
    this.matchBoost = 0,
    this.chainNext = false,
  });

  final String label;
  final String insertText;
  final String? detail;
  final IconData? icon;
  final SuggestionKind kind;
  final int matchBoost;

  /// When true, accepting this suggestion appends a trailing space and
  /// immediately re-opens the popup for the next token — used for SQL
  /// keywords, table names, and `*` so picking `SELECT → * → FROM →
  /// users → …` flows without ever pressing Ctrl-Space.
  final bool chainNext;
}

enum SuggestionKind { column, alias, table, keyword, snippet }

/// Snapshot of the editor at the moment a suggestion is requested.
/// [manualTrigger] is set by `Ctrl-Space` / `⌃Space` — providers may use
/// it to widen results when the user explicitly asks "what's available?"
class SuggestRequest {
  const SuggestRequest({
    required this.text,
    required this.cursor,
    required this.token,
    required this.tokenStart,
    this.manualTrigger = false,
  });

  final String text;
  final int cursor;
  final String token;
  final int tokenStart;
  final bool manualTrigger;
}

typedef CodeSuggestProvider =
    FutureOr<List<CodeSuggestion>> Function(SuggestRequest);
