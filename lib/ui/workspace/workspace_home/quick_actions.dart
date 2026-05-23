import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../widgets/common.dart';

class QuickActions extends StatelessWidget {
  const QuickActions({
    super.key,
    required this.tint,
    required this.narrow,
    required this.onNewQuery,
    required this.onSearch,
  });

  final Color tint;
  final bool narrow;
  final VoidCallback onNewQuery;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final newQuery = _ActionTile(
      icon: Icons.add_rounded,
      title: 'New query',
      subtitle: 'Open a blank SQL editor',
      shortcut: '⌘N',
      tint: tint,
      onTap: onNewQuery,
    );
    final search = _ActionTile(
      icon: Icons.search_rounded,
      title: 'Search everything',
      subtitle: 'Tables, queries & actions',
      shortcut: '⌘K',
      tint: tint,
      onTap: onSearch,
    );

    if (narrow) {
      return Column(
        children: [
          newQuery,
          const SizedBox(height: 10),
          search,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: newQuery),
        const SizedBox(width: 12),
        Expanded(child: search),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.shortcut,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String shortcut;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: hovering ? AppColors.surfaceHover : AppColors.surface,
          borderRadius: Radii.brMd,
          border: Border.all(
            color: hovering ? tint.withValues(alpha: 0.55) : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: hovering ? 0.20 : 0.12),
                borderRadius: Radii.brSm,
              ),
              child: Icon(icon, size: 18, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.ui(
                      size: 13,
                      weight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTheme.ui(
                      size: 11,
                      weight: FontWeight.w400,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            KbdChip(shortcut),
          ],
        ),
      ),
    );
  }
}
