import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// What a palette row represents. The ordering of the enum is also the
/// section ordering of the idle (empty-query) view and the tie-break order
/// when two search hits score equally.
enum PaletteKind {
  openTab,
  command,
  recent,
  favorite,
  savedQuery,
  connection,
  table,
}

extension PaletteKindX on PaletteKind {
  /// Uppercase eyebrow shown above each group in the idle view.
  String get section => switch (this) {
    PaletteKind.openTab => 'Open tabs',
    PaletteKind.command => 'Commands',
    PaletteKind.recent => 'Recent',
    PaletteKind.favorite => 'Pinned',
    PaletteKind.savedQuery => 'Saved queries',
    PaletteKind.connection => 'Connections',
    PaletteKind.table => 'Tables',
  };

  /// (label, tint) for the trailing chip.
  (String, Color) get chip => switch (this) {
    PaletteKind.openTab => ('tab', AppColors.accent),
    PaletteKind.command => ('action', AppColors.accent),
    PaletteKind.recent => ('recent', AppColors.warning),
    PaletteKind.favorite => ('pinned', AppColors.warning),
    PaletteKind.savedQuery => ('query', AppColors.tJson),
    PaletteKind.connection => ('conn', AppColors.success),
    PaletteKind.table => ('table', AppColors.info),
  };

  /// A small constant added to a hit's score so the more actionable kinds
  /// (a command, a tab to jump to) sort above a raw table name when fuzzy
  /// scores are close. Magnitudes here (0–8) sit below a typical fuzzy hit
  /// but the coverage term in [scoreItem] (up to +20) can outrank kind bias on
  /// its own, so this is more of a thumb on the scale than a strict
  /// tie-break.
  double get bias => switch (this) {
    PaletteKind.command => 8,
    PaletteKind.openTab => 6,
    PaletteKind.recent => 5,
    PaletteKind.favorite => 5,
    PaletteKind.savedQuery => 3,
    PaletteKind.connection => 2,
    PaletteKind.table => 0,
  };
}

class PaletteItem {
  PaletteItem({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.run,
    this.tokens = '',
    this.accent = false,
  });

  final PaletteKind kind;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback run;

  /// Extra hidden text folded into the search index — host names, fully
  /// qualified identifiers, command synonyms. Never displayed.
  final String tokens;

  /// When true the row's icon tile carries the accent tint even when not
  /// selected (used for the live connection / active tab).
  final bool accent;

  String get haystack => '$subtitle $tokens';
}

/// A search hit: the item plus its score and the matched character offsets
/// inside [PaletteItem.title] (used to highlight the run).
class PaletteHit {
  PaletteHit(this.item, this.score, this.highlight);

  final PaletteItem item;
  final double score;
  final List<int> highlight;
}
