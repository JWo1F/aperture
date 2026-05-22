import 'package:flutter/material.dart';

import '../../state/session_controller.dart';
import '../../theme/app_theme.dart';
import 'sidebar_deps.dart';

class SidebarFooter extends StatelessWidget {
  const SidebarFooter({super.key, required this.deps});

  final SidebarDeps deps;

  @override
  Widget build(BuildContext context) {
    final status = deps.session.status;
    final connected = status == ConnectionStatus.connected;
    final color = switch (status) {
      ConnectionStatus.connected => AppColors.success,
      ConnectionStatus.connecting => AppColors.warn,
      ConnectionStatus.lost => AppColors.warn,
      ConnectionStatus.error => AppColors.error,
      ConnectionStatus.disconnected => AppColors.textMuted,
    };
    final label = switch (status) {
      ConnectionStatus.connected => 'live',
      ConnectionStatus.connecting => 'connecting…',
      ConnectionStatus.lost => 'connection lost',
      ConnectionStatus.error => 'error',
      ConnectionStatus.disconnected => 'offline',
    };

    final tableCount = deps.catalog.schemas.fold<int>(
      0,
      (a, b) => a + b.tables.length,
    );

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _LiveDot(color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTheme.ui(
              size: 10.5,
              color: AppColors.textMuted,
              weight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
          const Spacer(),
          if (connected && tableCount > 0)
            Text(
              '$tableCount ${tableCount == 1 ? 'table' : 'tables'}',
              style: AppTheme.ui(
                size: 10.5,
                color: AppColors.text4,
                weight: FontWeight.w400,
                letterSpacing: 0,
              ),
            ),
        ],
      ),
    );
  }
}

/// Steady status dot for the sidebar footer. Deliberately not animated:
/// a perpetual pulse keeps the whole app rendering at 60fps and never
/// lets it idle. Status is carried by [color] alone.
class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 12,
      child: Center(
        child: Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
