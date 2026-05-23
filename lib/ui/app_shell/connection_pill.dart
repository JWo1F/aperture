import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/connection_config.dart';
import '../../state/app_state.dart';
import '../../state/app_store.dart';
import '../../state/session_controller.dart';
import '../../state/tabs_controller.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../connection/connection_dialog.dart';
import '../widgets/common.dart';

/// Toolbar identity pill: dot · db icon · conn name · `/` · schema · chev.
/// Tap opens the connection switcher overlay.
class ConnectionPill extends StatefulWidget {
  const ConnectionPill({super.key});

  @override
  State<ConnectionPill> createState() => _ConnectionPillState();
}

class _ConnectionPillState extends State<ConnectionPill> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;

  void _open() {
    if (_entry != null) {
      _close();
      return;
    }
    _entry = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context).insert(_entry!);
  }

  void _close() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  Widget _buildOverlay(BuildContext _) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          offset: const Offset(0, 6),
          showWhenUnlinked: false,
          child: _ConnectionPickerPanel(onClose: _close),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // ConnectionPill reflects connection liveness, the active connection's
    // name, and the schema of the current tab. Subscribe to each slice
    // narrowly so widget-resize ticks and other unrelated notifications
    // don't repaint the pill.
    final status = context.select<SessionController, ConnectionStatus>(
      (s) => s.status,
    );
    final connName = context.select<SessionController, String?>(
      (s) => s.activeConnection?.name,
    );
    final connColor = context.select<SessionController, int?>(
      (s) => s.activeConnection?.color,
    );
    final schema = context.select<TabsController, String>(
      (t) => _activeSchema(t.activeTab) ?? 'public',
    );
    final tint = AppColors.connectionTint(connColor);
    final (Color dot, String connLabel) = switch (status) {
      ConnectionStatus.connected => (
        AppColors.success,
        connName ?? 'connected',
      ),
      ConnectionStatus.connecting => (AppColors.accent, 'connecting…'),
      ConnectionStatus.lost => (AppColors.warning, connName ?? 'lost'),
      ConnectionStatus.error => (AppColors.error, 'no connection'),
      ConnectionStatus.disconnected => (AppColors.textMuted, 'no connection'),
    };

    return CompositedTransformTarget(
      link: _link,
      child: Hoverable(
        onTap: _open,
        builder: (context, hovering) => Container(
          height: 26,
          padding: const EdgeInsets.only(left: 8, right: 8),
          decoration: BoxDecoration(
            color: hovering ? AppColors.surfaceHover : AppColors.surface,
            borderRadius: Radii.brSm,
            border: Border.all(
              color: hovering ? AppColors.borderStrong : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: dot.withValues(alpha: 0.32),
                      blurRadius: 3,
                      spreadRadius: 1.2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.storage_rounded,
                size: 11,
                color: connName != null ? tint : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  connLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.ui(
                    size: 11.5,
                    color: AppColors.textPrimary,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
              if (status == ConnectionStatus.connected) ...[
                const SizedBox(width: 6),
                Text(
                  '/',
                  style: AppTheme.ui(
                    size: 11.5,
                    color: AppColors.text4,
                    weight: FontWeight.w400,
                  ),
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    schema,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.ui(
                      size: 11.5,
                      color: AppColors.textSecondary,
                      weight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Icon(Icons.expand_more, size: 12, color: AppColors.text4),
            ],
          ),
        ),
      ),
    );
  }

  String? _activeSchema(WorkspaceTab? tab) {
    if (tab is TableTab) return tab.table.schema;
    if (tab is SchemaTab) return tab.table.schema;
    return null;
  }
}

class _ConnectionPickerPanel extends StatelessWidget {
  const _ConnectionPickerPanel({required this.onClose});

  final VoidCallback onClose;

  Future<void> _newConnection(BuildContext context) {
    onClose();
    return createConnectionFlow(context);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final active = context.select<SessionController, String?>(
      (s) => s.activeConnection?.id,
    );
    final connections = context.watch<AppStore>().connections;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 320,
        constraints: const BoxConstraints(maxHeight: 360),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: Radii.brMd,
          border: Border.all(color: AppColors.borderStrong),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (connections.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 14,
                  ),
                  child: Text(
                    'No saved connections yet.',
                    style: AppTheme.ui(size: 11.5, color: AppColors.textMuted),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: connections.length,
                    itemBuilder: (_, i) {
                      final c = connections[i];
                      return _ConnPickerRow(
                        config: c,
                        active: c.id == active,
                        onTap: () {
                          onClose();
                          if (c.id != active) appState.connect(c);
                        },
                      );
                    },
                  ),
                ),
              Divider(height: 9, color: AppColors.hairline),
              Hoverable(
                onTap: () => _newConnection(context),
                builder: (context, hovering) => Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: hovering
                        ? AppColors.surfaceHover
                        : Colors.transparent,
                    borderRadius: Radii.brSm,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.add, size: 13, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Text(
                        'New connection…',
                        style: AppTheme.ui(
                          size: 12,
                          color: AppColors.accent,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnPickerRow extends StatelessWidget {
  const _ConnPickerRow({
    required this.config,
    required this.active,
    required this.onTap,
  });

  final ConnectionConfig config;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = AppColors.connectionTint(config.color);
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? AppColors.accentSoft
              : (hovering ? AppColors.surfaceHover : Colors.transparent),
          borderRadius: Radii.brSm,
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: active ? tint : tint.withValues(alpha: 0.5),
                shape: BoxShape.circle,
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: tint.withValues(alpha: 0.5),
                          blurRadius: 5,
                        ),
                      ]
                    : null,
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
                    style: AppTheme.mono(
                      size: 12,
                      color: AppColors.textPrimary,
                      weight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    config.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.mono(
                      size: 10.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (active) Icon(Icons.check, size: 13, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}
