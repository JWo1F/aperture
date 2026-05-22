import 'package:flutter/material.dart';

import '../../models/connection_config.dart';
import '../../models/time_ago.dart';
import '../../theme/app_theme.dart';
import '../connection/connection_dialog.dart';
import '../widgets/common.dart';
import 'sidebar_deps.dart';

/// The body shown when no connection is active — header, list of saved
/// configs, and a "New connection" call to action that opens the
/// connection dialog.
class AllConnectionsList extends StatelessWidget {
  const AllConnectionsList({super.key, required this.deps});

  final SidebarDeps deps;

  Future<void> _newConnection(BuildContext context) async {
    final config = await showConnectionDialog(context);
    if (config == null) return;
    deps.registry.add(config);
    await deps.appState.connect(config);
  }

  @override
  Widget build(BuildContext context) {
    final list = deps.registry.all;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Row(
            children: [
              Text(
                'SAVED',
                style: AppTheme.ui(
                  size: 9.5,
                  color: AppColors.textMuted,
                  weight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(height: 1, color: AppColors.hairline),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: const BorderRadius.all(Radii.xs),
                  border: Border.all(color: AppColors.borderSoft),
                ),
                child: Text(
                  '${list.length}',
                  style: AppTheme.ui(
                    size: 9.5,
                    color: AppColors.text4,
                    weight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.power_off_outlined,
                        size: 20,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No connections',
                        style: AppTheme.ui(
                          size: 13,
                          color: AppColors.textSecondary,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Add a PostgreSQL connection to get started.',
                        style: AppTheme.ui(
                          size: 11.5,
                          color: AppColors.textMuted,
                          weight: FontWeight.w400,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: list.length,
                  itemBuilder: (_, i) =>
                      _SavedConnectionRow(config: list[i], deps: deps),
                ),
        ),
        Divider(height: 1, color: AppColors.hairline),
        Hoverable(
          onTap: () => _newConnection(context),
          builder: (context, hovering) => Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            color: hovering ? AppColors.sidebarRowHover : Colors.transparent,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Icon(Icons.add_rounded, size: 14, color: AppColors.accent),
                const SizedBox(width: 8),
                Text(
                  'New connection',
                  style: AppTheme.ui(
                    size: 12.5,
                    color: AppColors.accent,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SavedConnectionRow extends StatelessWidget {
  const _SavedConnectionRow({required this.config, required this.deps});

  final ConnectionConfig config;
  final SidebarDeps deps;

  Future<void> _edit(BuildContext context) async {
    final updated = await showConnectionDialog(context, existing: config);
    if (updated != null) deps.appState.updateConnection(updated);
  }

  void _delete() => deps.registry.remove(config.id);

  @override
  Widget build(BuildContext context) {
    final ts = config.lastConnectedAt;
    final tint = AppColors.connectionTint(config.color);
    return Hoverable(
      onTap: () => deps.appState.connect(config),
      builder: (context, hovering) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: hovering ? AppColors.surface : Colors.transparent,
          borderRadius: Radii.brSm,
          border: Border.all(
            color: hovering ? AppColors.borderSoft : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.16),
                borderRadius: const BorderRadius.all(Radii.xs),
                border: Border.all(color: tint.withValues(alpha: 0.5)),
              ),
              alignment: Alignment.center,
              child: Text(
                config.name.isEmpty
                    ? '?'
                    : config.name.substring(0, 1).toUpperCase(),
                style: AppTheme.ui(
                  size: 10.5,
                  color: tint,
                  weight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    config.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.ui(
                      size: 12.5,
                      weight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    ts == null ? config.summary : 'opened ${timeAgo(ts)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.ui(
                      size: 10.5,
                      color: AppColors.textMuted,
                      weight: FontWeight.w400,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            if (hovering) ...[
              _MiniIcon(icon: Icons.edit_outlined, onTap: () => _edit(context)),
              _MiniIcon(icon: Icons.delete_outline, onTap: _delete),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniIcon extends StatelessWidget {
  const _MiniIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(
          icon,
          size: 12,
          color: hovering ? AppColors.textPrimary : AppColors.textMuted,
        ),
      ),
    );
  }
}
