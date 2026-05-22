import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Single-line text that bolds and accent-tints the first case-insensitive
/// occurrence of [match]. Sidebar-local — the command palette has its own
/// variant tuned to its own row metrics.
class SidebarHighlightedText extends StatelessWidget {
  const SidebarHighlightedText({
    super.key,
    required this.text,
    required this.match,
    required this.style,
  });

  final String text;
  final String match;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (match.isEmpty) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final lower = text.toLowerCase();
    final idx = lower.indexOf(match);
    if (idx < 0) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final before = text.substring(0, idx);
    final hit = text.substring(idx, idx + match.length);
    final after = text.substring(idx + match.length);
    final hitStyle = style.copyWith(
      color: AppColors.accent,
      fontWeight: FontWeight.w700,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: before, style: style),
          TextSpan(text: hit, style: hitStyle),
          TextSpan(text: after, style: style),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
