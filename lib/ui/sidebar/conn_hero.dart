import 'package:flutter/material.dart';

import '../../models/connection_config.dart';
import '../../state/app_globals.dart';
import '../../state/session_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/context_menu.dart';

/// The connection card at the top of the sidebar: engine glyph, database
/// name, server tag, and a chevron that opens the connection menu.
///
/// Subscribes to [SessionController] directly: when this widget is mounted
/// as `const ConnHero()`, Flutter's element-update path short-circuits on
/// identical widget references, so a parent `ListenableBuilder` rebuild
/// alone would not refresh the hero's status text.
/// Darkens [color] by [amount] (0–1) while keeping its hue and
/// saturation — the connection tint has to stay recognisable.
Color _shade(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness * (1 - amount)).clamp(0.0, 1.0))
      .toColor();
}

class ConnHero extends StatelessWidget {
  const ConnHero({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState.session,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final session = appState.session;
    final conn = session.activeConnection;
    final connected = session.status == ConnectionStatus.connected;
    final menuEnabled = connected || session.status == ConnectionStatus.lost;
    final tint = AppColors.connectionTint(conn?.color);
    final engineIcon = conn?.engine == DbEngine.sqlite
        ? Icons.insert_drive_file_rounded
        : Icons.dns_rounded;

    final title = switch (session.status) {
      ConnectionStatus.connected => conn?.database ?? 'connected',
      ConnectionStatus.connecting => 'connecting…',
      ConnectionStatus.lost => conn?.database ?? 'lost',
      ConnectionStatus.error => 'connection failed',
      ConnectionStatus.disconnected => 'no connection',
    };

    final subtitleParts = <String>[
      if (conn?.name != null && conn!.name.isNotEmpty) conn.name,
      if (session.serverVersion != null) session.serverVersion!,
    ];
    final subtitle = subtitleParts.isEmpty ? null : subtitleParts.join('  ·  ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      child: Hoverable(
        onTap: menuEnabled
            ? () => openConnMenu(context, _anchorBelow(context))
            : null,
        onSecondaryTapDown: menuEnabled
            ? (d) => openConnMenu(context, d.globalPosition)
            : null,
        builder: (context, hovering) {
          final highlight = hovering && menuEnabled;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            decoration: BoxDecoration(
              borderRadius: Radii.brMd,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: highlight
                    ? [
                        tint.withValues(alpha: 0.14),
                        AppColors.surface,
                      ]
                    : [
                        AppColors.surface,
                        AppColors.surfaceAlt,
                      ],
              ),
              border: Border.all(
                color: highlight
                    ? tint.withValues(alpha: 0.5)
                    : AppColors.borderSoft,
                width: 1,
              ),
              boxShadow: highlight
                  ? [
                      BoxShadow(
                        color: tint.withValues(alpha: 0.2),
                        blurRadius: 12,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      // Darkened in HSL rather than lerped toward a
                      // hardcoded black: it keeps the connection's hue
                      // instead of desaturating toward grey, and it
                      // needs no colour literal.
                      colors: [tint, _shade(tint, 0.3)],
                    ),
                    borderRadius: Radii.brSm,
                    boxShadow: [
                      BoxShadow(
                        color: tint.withValues(alpha: 0.42),
                        blurRadius: 8,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    engineIcon,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.ui(
                          size: 13,
                          color: AppColors.textPrimary,
                          weight: FontWeight.w600,
                          letterSpacing: -0.1,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
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
                    ],
                  ),
                ),
                if (menuEnabled)
                  Icon(
                    Icons.unfold_more_rounded,
                    size: 14,
                    color: highlight
                        ? AppColors.textSecondary
                        : AppColors.text4,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Offset _anchorBelow(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    final origin = box.localToGlobal(Offset.zero);
    return Offset(origin.dx + 8, origin.dy + box.size.height + 2);
  }
}

void openConnMenu(BuildContext context, Offset position) {
  final loading = appState.catalog.isPhase1Loading;
  showContextMenu(
    context,
    globalPosition: position,
    entries: [
      CmItem(
        icon: Icons.refresh,
        label: loading ? 'Refreshing schema…' : 'Refresh schema',
        enabled: !loading,
        onTap: appState.refreshCatalog,
      ),
      const CmDivider(),
      CmItem(
        icon: Icons.power_settings_new,
        label: 'Disconnect',
        danger: true,
        onTap: appState.disconnect,
      ),
    ],
  );
}

/// Slim filter input mounted under the connection hero. Substring filter
/// is owned by the sidebar's root state — this widget only renders and
/// surfaces the controller back to it.
class SidebarSearchBar extends StatelessWidget {
  const SidebarSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
      child: AnimatedBuilder(
        animation: Listenable.merge([controller, focusNode]),
        builder: (context, _) {
          final hasText = controller.text.isNotEmpty;
          final focused = focusNode.hasFocus;
          return Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: focused ? AppColors.bg : AppColors.surface,
              borderRadius: Radii.brSm,
              border: Border.all(
                color: focused ? AppColors.accentRing : AppColors.borderSoft,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 13,
                  color: focused
                      ? AppColors.textSecondary
                      : AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    cursorColor: AppColors.accent,
                    cursorWidth: 1.4,
                    cursorHeight: 13,
                    style: AppTheme.ui(
                      size: 12,
                      color: AppColors.textPrimary,
                      weight: FontWeight.w400,
                      letterSpacing: 0,
                    ),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Filter tables, queries, schemas…',
                      hintStyle: AppTheme.ui(
                        size: 12,
                        color: AppColors.textMuted,
                        weight: FontWeight.w400,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
                if (hasText)
                  GestureDetector(
                    onTap: controller.clear,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.close_rounded,
                        size: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
