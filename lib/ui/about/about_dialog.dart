import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../widgets/common.dart';

/// Build/version is wired in here rather than read from pubspec at runtime
/// so the About dialog stays a zero-dependency widget. Bump on release.
const _version = '1.12.0';
const _tagline = 'A native macOS client for PostgreSQL and SQLite.';

Future<void> showAboutAperture(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.brLg,
        side: BorderSide(color: AppColors.borderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(Insets.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: Radii.brSm,
                    ),
                    child: Icon(
                      Icons.adjust,
                      size: 18,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aperture',
                        style: AppTheme.mono(
                          size: 16,
                          weight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ).copyWith(letterSpacing: 1.2),
                      ),
                      Text(
                        'version $_version',
                        style: AppTheme.mono(
                          size: 10.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: Insets.lg),
              Text(
                _tagline,
                style: AppTheme.ui(size: 12.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: Insets.md),
              _bullet('Connect to PostgreSQL or open SQLite databases'),
              _bullet('Browse schemas, edit rows inline, run SQL'),
              _bullet('Keychain-backed credentials, crash-safe storage'),
              _bullet('Browser-style history — ⌘[ / ⌘]'),
              _bullet('Command palette — ⌘K'),
              const SizedBox(height: Insets.xl),
              Align(
                alignment: Alignment.centerRight,
                child: AppButton(
                  label: 'Done',
                  primary: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _bullet(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 4),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 4,
        height: 4,
        margin: const EdgeInsets.only(top: 6, right: 8),
        decoration: BoxDecoration(
          color: AppColors.accent,
          shape: BoxShape.circle,
        ),
      ),
      Expanded(
        child: Text(
          text,
          style: AppTheme.ui(size: 11.5, color: AppColors.textSecondary),
        ),
      ),
    ],
  ),
);
