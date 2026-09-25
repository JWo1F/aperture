import 'package:flutter/material.dart';

import '../../../models/connection_config.dart';
import '../../../models/time_ago.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import '../../widgets/common.dart';

IconData _engineIcon(ConnectionConfig c) =>
    c.engine == DbEngine.sqlite ? Hgi.fileDatabase : Hgi.database01;

String _engineLabel(ConnectionConfig c) =>
    c.engine == DbEngine.sqlite ? 'SQLite' : 'PostgreSQL';

/// Connection-tinted square holding the engine glyph.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.config, required this.size});

  final ConnectionConfig config;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tint = AppColors.connectionTint(config.color);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.15),
        borderRadius: BorderRadius.all(Radius.circular(size * 0.26)),
        border: Border.all(color: tint.withValues(alpha: 0.4)),
      ),
      child: Icon(_engineIcon(config), size: size * 0.48, color: tint),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: Radii.brSm,
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: AppColors.textMuted),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.ui(
                size: 10.5,
                weight: FontWeight.w500,
                color: AppColors.textSecondary,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditButton extends StatelessWidget {
  const _EditButton({required this.onTap, required this.visible});

  final VoidCallback onTap;

  /// Hidden until the card is hovered, but always laid out so the card
  /// doesn't reflow when it appears.
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Edit connection',
      child: Hoverable(
        onTap: onTap,
        builder: (context, hovering) => Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovering
                ? AppColors.surfaceHover
                : AppColors.surfaceHover.withValues(alpha: 0),
            borderRadius: Radii.brSm,
          ),
          child: Icon(
            Hgi.edit02,
            size: 14,
            color: visible
                ? (hovering ? AppColors.textPrimary : AppColors.textMuted)
                : Colors.transparent,
          ),
        ),
      ),
    );
  }
}

/// The most recently used connection, given the width of the page and a
/// labelled Connect action.
class ResumeCard extends StatelessWidget {
  const ResumeCard({
    super.key,
    required this.config,
    required this.onConnect,
    required this.onEdit,
    required this.compact,
  });

  final ConnectionConfig config;
  final VoidCallback onConnect;
  final VoidCallback onEdit;

  /// Drops the Connect button so the details keep their width; the whole
  /// card still connects on click.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tint = AppColors.connectionTint(config.color);
    final last = config.lastConnectedAt;
    final queries = config.savedQueries.length;
    final tables = config.recentTables.length;
    return Hoverable(
      onTap: onConnect,
      builder: (context, hovering) {
        final base = hovering ? AppColors.surfaceHover : AppColors.surface;
        return Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
          decoration: BoxDecoration(
            borderRadius: Radii.brLg,
            border: Border.all(
              color: hovering ? tint.withValues(alpha: 0.6) : AppColors.border,
            ),
            // A gradient replaces `color` rather than painting over it, so the
            // surface is blended into the tinted end.
            gradient: LinearGradient(
              colors: [
                Color.alphaBlend(
                  tint.withValues(alpha: hovering ? 0.14 : 0.09),
                  base,
                ),
                base,
              ],
              stops: const [0, 0.55],
            ),
          ),
          child: Row(
            children: [
              _Avatar(config: config, size: 48),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CONTINUE WHERE YOU LEFT OFF',
                      style: AppTheme.eyebrow(color: tint),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      config.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.ui(
                        size: 17,
                        weight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      config.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.mono(
                        size: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Chip(_engineLabel(config)),
                        if (config.readOnly)
                          const _Chip('read-only', icon: Hgi.lock),
                        if (queries > 0)
                          _Chip(
                            '$queries saved ${queries == 1 ? 'query' : 'queries'}',
                            icon: Hgi.sourceCode,
                          ),
                        if (tables > 0)
                          _Chip(
                            '$tables recent ${tables == 1 ? 'table' : 'tables'}',
                            icon: Hgi.table01,
                          ),
                        if (last != null)
                          _Chip(timeAgo(last), icon: Hgi.clock01),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _EditButton(onTap: onEdit, visible: hovering),
              if (!compact) ...[
                const SizedBox(width: 6),
                Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: hovering ? AppColors.accentHover : AppColors.accent,
                    borderRadius: Radii.brSm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Connect',
                        style: AppTheme.ui(
                          size: 12.5,
                          weight: FontWeight.w500,
                          color: Colors.white,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Hgi.arrowRight01,
                        size: 14,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class ConnectionCard extends StatelessWidget {
  const ConnectionCard({
    super.key,
    required this.config,
    required this.onConnect,
    required this.onEdit,
  });

  final ConnectionConfig config;
  final VoidCallback onConnect;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final tint = AppColors.connectionTint(config.color);
    final last = config.lastConnectedAt;
    return Hoverable(
      onTap: onConnect,
      builder: (context, hovering) => Container(
        height: 112,
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: hovering ? AppColors.surfaceHover : AppColors.surface,
          borderRadius: Radii.brMd,
          border: Border.all(
            color: hovering ? tint.withValues(alpha: 0.6) : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Avatar(config: config, size: 32),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        config.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.ui(
                          size: 13,
                          weight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        _engineLabel(config),
                        style: AppTheme.ui(
                          size: 11,
                          weight: FontWeight.w400,
                          color: AppColors.textMuted,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                _EditButton(onTap: onEdit, visible: hovering),
              ],
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                config.summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.mono(size: 11, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Row(
                children: [
                  if (config.readOnly) ...[
                    Icon(Hgi.lock, size: 11, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      'read-only',
                      style: AppTheme.mono(
                        size: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    last == null ? 'never opened' : timeAgo(last),
                    style: AppTheme.mono(size: 10, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
