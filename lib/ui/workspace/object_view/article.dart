import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// Centred, scrolling page the object tab lays both faces out on.
class Article extends StatelessWidget {
  const Article({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bg,
      child: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(40, 28, 40, 60),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const SizedBox(height: 28),
                    children[i],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ArticleSection extends StatelessWidget {
  const ArticleSection({
    super.key,
    required this.title,
    required this.children,
    this.count,
  });

  final String title;
  final int? count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              title.toUpperCase(),
              style: AppTheme.mono(
                size: 10.5,
                color: AppColors.textMuted,
                weight: FontWeight.w600,
              ).copyWith(letterSpacing: 0.08 * 10.5),
            ),
            if (count != null && count! > 0) ...[
              const SizedBox(width: 6),
              Text(
                '$count',
                style: AppTheme.mono(size: 10.5, color: AppColors.text4),
              ),
            ],
            const SizedBox(width: 8),
            Expanded(child: Container(height: 1, color: AppColors.hairline)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: Radii.brSm,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Container(height: 1, color: AppColors.borderSoft),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class ArticleRow extends StatelessWidget {
  const ArticleRow({super.key, required this.child, this.highlighted = false});

  final Widget child;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: highlighted
          ? AppColors.surfaceHover
          : AppColors.surfaceHover.withValues(alpha: 0),
      child: child,
    );
  }
}

class ArticleNote extends StatelessWidget {
  const ArticleNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Text(
        text,
        style: AppTheme.ui(
          size: 12,
          weight: FontWeight.w400,
          color: AppColors.textMuted,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
