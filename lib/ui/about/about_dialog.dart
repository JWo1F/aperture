import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_globals.dart';
import '../../theme/app_theme.dart';
import '../../theme/hugeicons.dart';
import '../widgets/common.dart';

/// Build/version is wired in here rather than read from pubspec at runtime
/// so the About dialog stays a zero-dependency widget. Bump on release.
const _version = '1.33.3';
const _author = 'Aleksandr Ivashkin';
const _copyrightYear = 2026;

Future<void> showAboutAperture(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _AboutDialog(),
  );
}

class _AboutDialog extends StatelessWidget {
  const _AboutDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.brLg,
        side: BorderSide(color: AppColors.borderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Scrolls only when the window is too short to fit it all; the
            // footer with Done stays pinned.
            const Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(),
                    Padding(
                      padding: EdgeInsets.fromLTRB(24, 4, 24, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _FeatureGrid(),
                          SizedBox(height: 20),
                          _Author(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _Footer(onDone: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(
              AppColors.accent.withValues(alpha: 0.10),
              AppColors.surface,
            ),
            AppColors.surface,
          ],
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.25),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(20)),
              child: Image.asset(
                'assets/brand/app_icon.png',
                width: 84,
                height: 84,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Aperture',
            style: AppTheme.ui(
              size: 24,
              weight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.7,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'A close look at PostgreSQL and SQLite.',
            textAlign: TextAlign.center,
            style: AppTheme.ui(
              size: 12.5,
              weight: FontWeight.w400,
              color: AppColors.textSecondary,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 12),
          const _VersionChip(),
        ],
      ),
    );
  }
}

/// Click copies the version, for pasting into a bug note.
class _VersionChip extends StatelessWidget {
  const _VersionChip();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Copy version',
      child: Hoverable(
        onTap: () {
          Clipboard.setData(const ClipboardData(text: 'Aperture $_version'));
          appState.toasts.info('Aperture $_version', title: 'Version copied');
        },
        builder: (context, hovering) => Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: hovering ? AppColors.surfaceHover : AppColors.surfaceAlt,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            border: Border.all(
              color: hovering ? AppColors.borderStrong : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Version $_version',
                style: AppTheme.mono(
                  size: 11,
                  weight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ).copyWith(height: 1.0),
              ),
              const SizedBox(width: 6),
              Icon(Hgi.copy01, size: 11, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid();

  static const _features = [
    (Hgi.database01, 'Two engines', 'PostgreSQL servers and SQLite files'),
    (Hgi.editTable, 'Edit in place', 'Stage row edits, review, then apply'),
    (Hgi.chartRelationship, 'Query plans', 'EXPLAIN as a tree, with advice'),
    (Hgi.command, 'Keyboard first', '⌘K palette, ⌘[ ⌘] history'),
    (Hgi.databaseExport, 'Export', 'Results and tables to CSV or Markdown'),
    (Hgi.lockKey, 'Credentials', 'Stored, or fetched by any command'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < _features.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _Feature(_features[i])),
                const SizedBox(width: 8),
                Expanded(child: _Feature(_features[i + 1])),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature(this.feature);

  final (IconData, String, String) feature;

  @override
  Widget build(BuildContext context) {
    final (icon, title, body) = feature;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: Radii.brMd,
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.accent),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.ui(
                    size: 12,
                    weight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.ui(
                    size: 10.5,
                    weight: FontWeight.w400,
                    color: AppColors.textMuted,
                    letterSpacing: 0,
                  ).copyWith(height: 1.25),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Author extends StatelessWidget {
  const _Author();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.accentRing),
          ),
          child: Text(
            'AI',
            style: AppTheme.ui(
              size: 12,
              weight: FontWeight.w700,
              color: AppColors.accent,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DESIGNED & BUILT BY', style: AppTheme.eyebrow()),
              const SizedBox(height: 2),
              Text(
                _author,
                style: AppTheme.ui(
                  size: 13.5,
                  weight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '© $_copyrightYear $_author',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.ui(
                size: 11,
                weight: FontWeight.w400,
                color: AppColors.textMuted,
                letterSpacing: 0,
              ),
            ),
          ),
          AppButton(label: 'Done', primary: true, onPressed: onDone),
        ],
      ),
    );
  }
}
