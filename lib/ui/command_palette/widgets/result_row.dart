import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import '../item_model.dart';

class PaletteResultRow extends StatelessWidget {
  const PaletteResultRow({
    super.key,
    required this.item,
    required this.highlight,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final PaletteItem item;
  final List<int> highlight;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final (chipLabel, chipColor) = item.kind.chip;
    final tileAccent = selected || item.accent;
    return MouseRegion(
      onEnter: (_) => onHover(),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 46,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentSoft : Colors.transparent,
            borderRadius: Radii.brSm,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 3,
                child: selected
                    ? Container(
                        height: 18,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 7),
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tileAccent
                      ? AppColors.accent.withValues(alpha: 0.16)
                      : AppColors.surface2,
                  borderRadius: Radii.brSm,
                  border: Border.all(
                    color: tileAccent
                        ? AppColors.accent.withValues(alpha: 0.30)
                        : AppColors.border,
                  ),
                ),
                child: Icon(
                  item.icon,
                  size: 15,
                  color: tileAccent ? AppColors.accent : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HighlightedText(
                      text: item.title,
                      highlight: highlight,
                      style: AppTheme.mono(
                        size: 12.5,
                        weight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                      matchColor: AppColors.accentHover,
                    ),
                    if (item.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.ui(
                          size: 11,
                          weight: FontWeight.w400,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _KindChip(label: chipLabel, color: chipColor),
              SizedBox(
                width: 30,
                child: selected
                    ? Center(
                        child: Icon(
                          Hgi.cornerDownLeft,
                          size: 13,
                          color: AppColors.accent,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.highlight,
    required this.style,
    required this.matchColor,
  });

  final String text;
  final List<int> highlight;
  final TextStyle style;
  final Color matchColor;

  @override
  Widget build(BuildContext context) {
    if (highlight.isEmpty) {
      return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }
    final hit = List<bool>.filled(text.length, false);
    for (final i in highlight) {
      if (i >= 0 && i < text.length) hit[i] = true;
    }
    final matchStyle = style.copyWith(
      color: matchColor,
      fontWeight: FontWeight.w700,
    );
    final spans = <TextSpan>[];
    var i = 0;
    while (i < text.length) {
      final on = hit[i];
      var j = i;
      while (j < text.length && hit[j] == on) {
        j++;
      }
      spans.add(TextSpan(text: text.substring(i, j), style: on ? matchStyle : style));
      i = j;
    }
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: Radii.brSm,
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: AppTheme.mono(size: 9.5, color: color, weight: FontWeight.w600),
      ),
    );
  }
}
