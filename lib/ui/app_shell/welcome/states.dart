import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import '../../widgets/common.dart';
import '../../widgets/command_key.dart';

/// Spinner + caption while a connection opens and its first schema fetch
/// lands. Two captions, one per gap, so the user can tell whether the
/// network round-trip or the catalog read is the slow part.
class WelcomePreparing extends StatelessWidget {
  const WelcomePreparing({
    super.key,
    required this.connecting,
    required this.connectionName,
  });

  final bool connecting;
  final String? connectionName;

  @override
  Widget build(BuildContext context) {
    final name = connectionName;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: Radii.brLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connecting ? 'Connecting…' : 'Loading schemas…',
                  style: AppTheme.ui(
                    size: 13,
                    weight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (name != null && name.isNotEmpty)
                  Text(
                    name,
                    style: AppTheme.mono(size: 11, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WelcomeError extends StatelessWidget {
  const WelcomeError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: Radii.brMd,
        border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Hgi.alertCircle, size: 16, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Couldn't connect",
                  style: AppTheme.ui(
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  message,
                  style: AppTheme.mono(
                    size: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// No saved connections yet: one large call to action.
class WelcomeEmpty extends StatelessWidget {
  const WelcomeEmpty({super.key, required this.onNew});

  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onNew,
      builder: (context, hovering) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        decoration: BoxDecoration(
          color: hovering ? AppColors.surfaceHover : AppColors.surface,
          borderRadius: Radii.brLg,
          border: Border.all(
            color: hovering ? AppColors.accentRing : AppColors.border,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: Radii.brMd,
              ),
              child: Icon(Hgi.add01, size: 20, color: AppColors.accent),
            ),
            const SizedBox(height: 14),
            Text(
              'Add your first connection',
              style: AppTheme.ui(
                size: 15,
                weight: FontWeight.w600,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'A PostgreSQL server or a SQLite file on this Mac.',
              textAlign: TextAlign.center,
              style: AppTheme.ui(
                size: 12.5,
                weight: FontWeight.w400,
                color: AppColors.textMuted,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shortcut hints plus the About link.
class WelcomeFooter extends StatelessWidget {
  const WelcomeFooter({super.key, required this.onAbout});

  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) {
    Widget hint(String key, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KbdChip(key),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.ui(
              size: 11.5,
              weight: FontWeight.w400,
              color: AppColors.textMuted,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );

    return Wrap(
      spacing: 18,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        hint(commandLabel('K'), 'Search connections & commands'),
        hint(commandLabel('L'), 'Activity log'),
        Hoverable(
          onTap: onAbout,
          builder: (context, hovering) => Text(
            'About Aperture',
            style: AppTheme.ui(
              size: 11.5,
              weight: FontWeight.w400,
              color: hovering ? AppColors.textPrimary : AppColors.textMuted,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}
