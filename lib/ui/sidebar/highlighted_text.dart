import 'package:flutter/material.dart';

import '../../models/name_match.dart';
import '../../theme/app_theme.dart';

/// Single-line text that bolds and accent-tints the letters [nameMatch]
/// finds for [match] — a substring, or the initials of an acronym match. Sidebar-local — the command palette has its own
/// variant tuned to its own row metrics.
class SidebarHighlightedText extends StatelessWidget {
  const SidebarHighlightedText({
    super.key,
    required this.text,
    required this.match,
    required this.style,
    this.trailing,
  });

  final String text;
  final String match;
  final TextStyle style;

  /// Appended in the same paragraph, so the ellipsis trims it before [text].
  final InlineSpan? trailing;

  @override
  Widget build(BuildContext context) {
    final hits = match.isEmpty ? null : nameMatch(text, match)?.toSet();
    final hitStyle = style.copyWith(
      color: AppColors.accent,
      fontWeight: FontWeight.w700,
    );
    final spans = <InlineSpan>[];
    var runStart = 0;
    for (var i = 1; i <= text.length; i++) {
      final boundary =
          i == text.length ||
          (hits?.contains(i) ?? false) != (hits?.contains(runStart) ?? false);
      if (!boundary) continue;
      spans.add(
        TextSpan(
          text: text.substring(runStart, i),
          style: (hits?.contains(runStart) ?? false) ? hitStyle : style,
        ),
      );
      runStart = i;
    }
    return Text.rich(
      TextSpan(children: [...spans, ?trailing]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
