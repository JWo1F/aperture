import 'package:flutter/material.dart';

import '../../../models/connection_config.dart';
import '../../../models/time_ago.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import '../../widgets/common.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.connection,
    required this.tint,
    required this.serverVersion,
    required this.refreshing,
    required this.onRefresh,
    required this.onSearch,
    required this.onNewQuery,
    required this.compact,
  });

  final ConnectionConfig? connection;
  final Color tint;
  final String? serverVersion;
  final bool refreshing;
  final VoidCallback onRefresh;
  final VoidCallback onSearch;
  final VoidCallback onNewQuery;

  /// Collapses the actions to icon-only so the name keeps its room.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final conn = connection;
    final engine = conn?.engine == DbEngine.sqlite ? 'SQLite' : 'PostgreSQL';
    final version = serverVersion;
    final connectedAt = conn?.lastConnectedAt;
    final summary = conn?.summary ?? '';

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.14),
            borderRadius: Radii.brMd,
            border: Border.all(color: tint.withValues(alpha: 0.35)),
          ),
          child: Icon(Hgi.database01, size: 20, color: tint),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      conn?.name ?? 'Database',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.ui(
                        size: 18,
                        weight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _StatusTag(connectedAt: connectedAt),
                ],
              ),
              const SizedBox(height: 3),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: engine,
                      style: AppTheme.ui(
                        size: 11.5,
                        weight: FontWeight.w500,
                        color: AppColors.textSecondary,
                        letterSpacing: 0,
                      ),
                    ),
                    if (version != null && version.isNotEmpty)
                      TextSpan(text: ' $version'),
                    if (summary.isNotEmpty) ...[
                      TextSpan(
                        text: '  ·  ',
                        style: TextStyle(color: AppColors.text4),
                      ),
                      TextSpan(text: summary),
                    ],
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.mono(size: 11, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        _HeaderButton(
          icon: Hgi.refresh,
          label: refreshing ? 'Refreshing…' : 'Refresh',
          showLabel: !compact,
          onTap: refreshing ? null : onRefresh,
        ),
        const SizedBox(width: 8),
        _HeaderButton(
          icon: Hgi.search01,
          label: 'Search',
          shortcut: '⌘K',
          showLabel: !compact,
          onTap: onSearch,
        ),
        const SizedBox(width: 8),
        _HeaderButton(
          icon: Hgi.add01,
          label: 'New query',
          shortcut: '⌘N',
          primary: true,
          showLabel: !compact,
          onTap: onNewQuery,
        ),
      ],
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.connectedAt});

  final DateTime? connectedAt;

  @override
  Widget build(BuildContext context) {
    final since = connectedAt;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: Radii.brSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            since == null ? 'Connected' : 'Connected ${timeAgo(since)}',
            style: AppTheme.ui(
              size: 10.5,
              weight: FontWeight.w500,
              color: AppColors.success,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

/// Header action: icon + label + optional shortcut chip. Hover swaps colours
/// instantly; `AppButton` cross-fades, and the home screen carries no motion.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.showLabel,
    this.shortcut,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final String? shortcut;
  final bool primary;
  final bool showLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Hoverable(
      onTap: onTap,
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      builder: (context, hovering) {
        final Color bg;
        final Color fg;
        final Color border;
        if (primary) {
          bg = hovering ? AppColors.accentHover : AppColors.accent;
          fg = Colors.white;
          border = bg;
        } else {
          bg = hovering && enabled ? AppColors.surfaceHover : AppColors.surface;
          fg = enabled ? AppColors.textPrimary : AppColors.textMuted;
          border = hovering && enabled
              ? AppColors.borderStrong
              : AppColors.border;
        }
        final withChip = showLabel && shortcut != null;
        final button = Container(
          height: 30,
          padding: EdgeInsets.only(
            left: showLabel ? 10 : 8,
            right: withChip ? 6 : (showLabel ? 12 : 8),
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: Radii.brSm,
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              if (showLabel) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppTheme.ui(
                    size: 12,
                    weight: FontWeight.w500,
                    color: fg,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
              if (withChip) ...[
                const SizedBox(width: 8),
                KbdChip(shortcut!, onAccent: primary),
              ],
            ],
          ),
        );
        if (showLabel) return button;
        final tip = shortcut == null ? label : '$label  $shortcut';
        return Tooltip(message: tip, child: button);
      },
    );
  }
}
