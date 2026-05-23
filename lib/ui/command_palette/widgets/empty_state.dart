import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

class PaletteEmptyState extends StatelessWidget {
  const PaletteEmptyState({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final searching = query.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 44, 32, 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            searching ? Icons.search_off_rounded : Icons.bolt_outlined,
            size: 30,
            color: AppColors.text4,
          ),
          const SizedBox(height: 14),
          Text(
            searching ? 'No matches for "$query"' : 'Nothing to jump to yet',
            style: AppTheme.ui(
              size: 13,
              weight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            searching
                ? 'Try a table name, a connection, or a command like "theme".'
                : 'Connect to a database to search its tables and queries.',
            textAlign: TextAlign.center,
            style: AppTheme.ui(
              size: 11.5,
              weight: FontWeight.w400,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
