import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/connection_config.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'connection_dialog.dart';

/// Toolbar dropdown showing the active connection and letting the user switch
/// between saved ones or add a new connection inline.
class ConnectionMenu extends StatefulWidget {
  const ConnectionMenu({super.key});

  @override
  State<ConnectionMenu> createState() => _ConnectionMenuState();
}

class _ConnectionMenuState extends State<ConnectionMenu> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  bool _hover = false;

  void _open() {
    if (_entry != null) return _close();
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
          child: _Panel(onClose: _close),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final conn = state.activeConnection;
    final (Color color, String label) = switch (state.status) {
      ConnectionStatus.connected => (
          AppColors.success,
          conn?.name ?? 'Connected',
        ),
      ConnectionStatus.connecting => (AppColors.accent, 'Connecting…'),
      ConnectionStatus.error => (AppColors.error, 'Connection failed'),
      ConnectionStatus.disconnected => (
          AppColors.textMuted,
          'No connection',
        ),
    };

    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: _open,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 28,
            padding: const EdgeInsets.only(left: 10, right: 8),
            decoration: BoxDecoration(
              color: _hover ? AppColors.surfaceHover : AppColors.bg,
              borderRadius: Radii.brSm,
              border: Border.all(
                color: _hover ? AppColors.borderStrong : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.ui(
                      size: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.unfold_more,
                  size: 13,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.onClose});
  final VoidCallback onClose;

  Future<void> _newConnection(BuildContext context) async {
    onClose();
    final state = context.read<AppState>();
    final config = await showConnectionDialog(context);
    if (config == null) return;
    state.addConnection(config);
    await state.connect(config);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 320,
        constraints: const BoxConstraints(maxHeight: 360),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: Radii.brMd,
          border: Border.all(color: AppColors.borderStrong),
          boxShadow: const [
            BoxShadow(
              color: Color(0x88000000),
              blurRadius: 30,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  Text('Connections', style: AppTheme.eyebrow()),
                  const Spacer(),
                  Text(
                    '${state.connections.length}',
                    style: AppTheme.eyebrow(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Flexible(
              child: state.connections.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      child: Text(
                        'No saved connections yet.',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      shrinkWrap: true,
                      itemCount: state.connections.length,
                      itemBuilder: (_, i) {
                        final c = state.connections[i];
                        final isActive = state.activeConnection?.id == c.id;
                        return _ConnectionEntry(
                          config: c,
                          active: isActive,
                          onTap: () {
                            onClose();
                            if (!isActive) state.connect(c);
                          },
                          onEdit: () async {
                            onClose();
                            final updated = await showConnectionDialog(
                              context,
                              existing: c,
                            );
                            if (updated != null) state.updateConnection(updated);
                          },
                          onDelete: () {
                            state.removeConnection(c.id);
                          },
                        );
                      },
                    ),
            ),
            Divider(height: 1, color: AppColors.border),
            InkWell(
              onTap: () => _newConnection(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.add,
                      size: 14,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'New connection…',
                      style: AppTheme.ui(
                        size: 12.5,
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
    );
  }
}

class _ConnectionEntry extends StatefulWidget {
  const _ConnectionEntry({
    required this.config,
    required this.active,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final ConnectionConfig config;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_ConnectionEntry> createState() => _ConnectionEntryState();
}

class _ConnectionEntryState extends State<_ConnectionEntry> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: widget.active
                ? AppColors.accentSoft
                : (_hover ? AppColors.surfaceHover : Colors.transparent),
            borderRadius: Radii.brSm,
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: widget.active
                      ? AppColors.success
                      : AppColors.borderStrong,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.config.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.ui(
                        size: 12.5,
                        weight: FontWeight.w500,
                        color: widget.active
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      widget.config.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.mono(
                        size: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (_hover) ...[
                _IconMini(
                    icon: Icons.edit_outlined, onTap: widget.onEdit),
                const SizedBox(width: 2),
                _IconMini(
                    icon: Icons.delete_outline, onTap: widget.onDelete),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IconMini extends StatelessWidget {
  const _IconMini({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(icon, size: 12, color: AppColors.textMuted),
      ),
    );
  }
}
