import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import 'common.dart';

/// A line in a context menu — either an action or a separator.
sealed class CmEntry {
  const CmEntry();
}

class CmItem extends CmEntry {
  const CmItem({
    required this.label,
    required this.onTap,
    this.icon,
    this.shortcut,
    this.danger = false,
    this.enabled = true,
  });

  final String label;
  final IconData? icon;
  final String? shortcut;
  final VoidCallback onTap;
  final bool danger;
  final bool enabled;
}

class CmDivider extends CmEntry {
  const CmDivider();
}

/// Shows a context menu anchored at [globalPosition]. Dismisses on outside
/// click or Escape. Entries that aren't [CmItem] (dividers) are non-clickable.
void showContextMenu(
  BuildContext context, {
  required Offset globalPosition,
  required List<CmEntry> entries,
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  void close() {
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => _ContextMenuOverlay(
      position: globalPosition,
      entries: entries,
      onClose: close,
    ),
  );
  overlay.insert(entry);
}

class _ContextMenuOverlay extends StatelessWidget {
  const _ContextMenuOverlay({
    required this.position,
    required this.entries,
    required this.onClose,
  });

  final Offset position;
  final List<CmEntry> entries;
  final VoidCallback onClose;

  static const double _menuWidth = 240;
  static const double _itemHeight = 28;
  static const double _dividerHeight = 7;
  static const double _verticalPad = 6;

  double _estimatedHeight() {
    var h = _verticalPad * 2;
    for (final e in entries) {
      h += e is CmDivider ? _dividerHeight : _itemHeight;
    }
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final estimated = _estimatedHeight();

    var x = position.dx;
    var y = position.dy;
    if (x + _menuWidth + 8 > media.width) x = media.width - _menuWidth - 8;
    if (y + estimated + 8 > media.height) y = media.height - estimated - 8;
    if (x < 8) x = 8;
    if (y < 8) y = 8;

    // The menu sits in an overlay, outside the tree that owns focus, so
    // Escape only reaches it if something here holds focus. Without this
    // the documented dismissal did nothing and the grid's own Escape
    // handler cleared the cell selection behind the open menu instead.
    return FocusScope(
      autofocus: true,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): onClose,
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                onSecondaryTap: onClose,
              ),
            ),
            Positioned(
              left: x,
              top: y,
              // A tall menu (the cell menu reaches ~18 entries) would run
              // off the bottom of a short window with nothing to scroll.
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: media.height - 16),
                child: SingleChildScrollView(
                  child: _Menu(
                    entries: entries,
                    onClose: onClose,
                    width: _menuWidth,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({
    required this.entries,
    required this.onClose,
    required this.width,
  });

  final List<CmEntry> entries;
  final VoidCallback onClose;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: Radii.brMd,
          border: Border.all(color: AppColors.borderStrong),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final e in entries)
              if (e is CmDivider)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 3,
                    horizontal: 6,
                  ),
                  child: Divider(height: 1, color: AppColors.border),
                )
              else if (e is CmItem)
                _Row(item: e, onClose: onClose),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.onClose});

  final CmItem item;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final disabled = !item.enabled;
    return Hoverable(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onTap: disabled
          ? null
          : () {
              onClose();
              item.onTap();
            },
      builder: (context, hovering) {
        final hot = hovering && !disabled;
        // On hover the row paints accent for non-destructive items and the
        // danger tone for destructive ones; foreground flips to white either
        // way, mirroring the design's `.menu-item:hover` rule.
        final Color bg = hot
            ? (item.danger ? AppColors.error : AppColors.accent)
            : Colors.transparent;
        final Color fg = hot
            ? Colors.white
            : disabled
            ? AppColors.textMuted
            : (item.danger ? AppColors.error : AppColors.textPrimary);
        final Color iconColor = hot
            ? Colors.white.withValues(alpha: 0.85)
            : disabled
            ? AppColors.textMuted
            : (item.danger ? AppColors.error : AppColors.textSecondary);
        final Color shortcutColor = hot
            ? Colors.white.withValues(alpha: 0.85)
            : AppColors.textMuted;

        return Container(
          height: 26,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            children: [
              if (item.icon != null) ...[
                SizedBox(
                  width: 14,
                  child: Icon(item.icon, size: 13, color: iconColor),
                ),
                const SizedBox(width: 10),
              ] else
                const SizedBox(width: 24),
              Expanded(
                child: Text(
                  item.label,
                  // The row is a fixed 26px and the label column ~190px.
                  // Dynamic labels interpolate column names and qualified
                  // FK targets — `Follow → public.organization_members.id`
                  // wrapped to a second line and bled over the row below.
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.ui(
                    size: 12,
                    color: fg,
                    weight: FontWeight.w400,
                  ),
                ),
              ),
              if (item.shortcut != null)
                Text(
                  item.shortcut!,
                  style: AppTheme.mono(size: 10, color: shortcutColor),
                ),
            ],
          ),
        );
      },
    );
  }
}
