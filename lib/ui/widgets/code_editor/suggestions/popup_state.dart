import 'package:flutter/widgets.dart' show Offset;

import 'suggestion.dart';

/// Immutable snapshot of the autocomplete popup. `items.isEmpty` ⇒ hidden.
class PopupState {
  const PopupState({
    required this.items,
    required this.selected,
    required this.tokenStart,
    required this.cursor,
    required this.anchor,
  });

  const PopupState.hidden()
    : items = const [],
      selected = 0,
      tokenStart = 0,
      cursor = 0,
      anchor = Offset.zero;

  final List<CodeSuggestion> items;
  final int selected;
  final int tokenStart;
  final int cursor;
  final Offset anchor;

  bool get isHidden => items.isEmpty;

  PopupState copyWith({
    List<CodeSuggestion>? items,
    int? selected,
    int? tokenStart,
    int? cursor,
    Offset? anchor,
  }) => PopupState(
    items: items ?? this.items,
    selected: selected ?? this.selected,
    tokenStart: tokenStart ?? this.tokenStart,
    cursor: cursor ?? this.cursor,
    anchor: anchor ?? this.anchor,
  );
}
