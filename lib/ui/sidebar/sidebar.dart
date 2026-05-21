import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/connection_config.dart';
import '../../models/db_object.dart';
import '../../models/saved_query.dart';
import '../../models/time_ago.dart';
import '../../state/app_state.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../connection/connection_dialog.dart';
import '../widgets/common.dart';
import '../widgets/context_menu.dart';
import '../widgets/table_glyph.dart';

/// Sidebar v3 — modeled on the design handoff.
///
/// Layout (top → bottom):
///   1. `sb-conn` strip: db icon + active connection name + tag chip.
///   2. Scroll body: Favorites · Recents · Saved queries · Schemas
///      (each schema's tables/views are surfaced under tiny eyebrow rules).
///   3. Footer status row: dot + plain-text live-state.
class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final connected = state.status == ConnectionStatus.connected;

    return Container(
      width: state.preferences.sidebarWidth,
      // Match `var(--sidebar)` — sidebarTint at 86% alpha so the app's accent
      // halo and the workspace deep bg both bleed through slightly.
      color: AppColors.sidebarTint.withValues(alpha: 0.86),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ConnHeader(state: state),
          Expanded(
            child: connected
                ? _Body(state: state)
                : _AllConnectionsList(state: state),
          ),
          _FooterStatus(state: state),
        ],
      ),
    );
  }
}

// --- sb-conn strip --------------------------------------------------------

class _ConnHeader extends StatelessWidget {
  const _ConnHeader({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final conn = state.activeConnection;
    final connected = state.status == ConnectionStatus.connected;
    final label = switch (state.status) {
      ConnectionStatus.connected => conn?.database ?? 'connected',
      ConnectionStatus.connecting => 'connecting…',
      ConnectionStatus.lost => conn?.database ?? 'lost',
      ConnectionStatus.error => 'connection failed',
      ConnectionStatus.disconnected => 'no connection',
    };

    final version = state.serverVersion;
    final menuEnabled = connected || state.status == ConnectionStatus.lost;

    return Hoverable(
      onTap: menuEnabled
          ? () => _openConnMenu(context, state, _anchorBelow(context))
          : null,
      onSecondaryTapDown: menuEnabled
          ? (d) => _openConnMenu(context, state, d.globalPosition)
          : null,
      builder: (context, hovering) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
        decoration: BoxDecoration(
          color: hovering && menuEnabled
              ? AppColors.sidebarRowHover
              : Colors.transparent,
          border: Border(bottom: BorderSide(color: AppColors.hairline)),
        ),
        child: Row(
          children: [
            // Icon stays in the accent the design uses regardless of state;
            // connection liveness is surfaced by the footer dot.
            Icon(Icons.storage_rounded, size: 12, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.mono(
                  size: 11.5,
                  color: AppColors.textPrimary,
                  weight: FontWeight.w600,
                ),
              ),
            ),
            if (version != null) ...[
              Text(
                version,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.mono(size: 10.5, color: AppColors.text4),
              ),
              const SizedBox(width: 4),
            ],
            if (menuEnabled)
              Icon(
                Icons.expand_more,
                size: 13,
                color: hovering ? AppColors.textSecondary : AppColors.text4,
              ),
          ],
        ),
      ),
    );
  }

  /// Drop-anchor for the left-click menu — bottom-left of the conn row.
  Offset _anchorBelow(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    final origin = box.localToGlobal(Offset.zero);
    return Offset(origin.dx + 12, origin.dy + box.size.height + 2);
  }
}

void _openConnMenu(BuildContext context, AppState state, Offset position) {
  showContextMenu(
    context,
    globalPosition: position,
    entries: [
      CmItem(
        icon: Icons.refresh,
        label: state.isCatalogLoading ? 'Refreshing schema…' : 'Refresh schema',
        enabled: !state.isCatalogLoading,
        onTap: state.refreshCatalog,
      ),
      const CmDivider(),
      CmItem(
        icon: Icons.power_settings_new,
        label: 'Disconnect',
        danger: true,
        onTap: state.disconnect,
      ),
    ],
  );
}

// --- sections -------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final activeId = _activeTableQualifiedName(state);
    final activeQueryId = _activeQueryId(state);
    final favorites = state.favoriteTables;
    final favKeys = {for (final t in favorites) t.qualifiedKey};
    final recents = state.recents
        .where((t) => !favKeys.contains(t.qualifiedKey))
        .toList();
    final saved = state.savedQueries;
    final schemas = state.schemas;

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      children: [
        if (favorites.isNotEmpty)
          _Section(
            label: 'Favorites',
            count: favorites.length,
            children: [
              for (final t in favorites)
                _TreeRow(
                  indent: 0,
                  twisty: Icon(Icons.star, size: 9, color: AppColors.warn),
                  icon: t.isView
                      ? Icon(
                          Icons.visibility_outlined,
                          size: 11,
                          color: AppColors.textMuted,
                        )
                      : TableGlyph(size: 11, color: AppColors.textMuted),
                  name: '${t.schema}.${t.name}',
                  active: t.qualifiedName == activeId,
                  onTap: () => state.openTable(t),
                  onSecondaryTapDown: (d) =>
                      _openTableMenu(context, state, t, d.globalPosition),
                ),
            ],
          ),
        if (recents.isNotEmpty)
          _Section(
            label: 'Recents',
            count: recents.length,
            children: [
              for (final t in recents.take(8))
                _TreeRow(
                  indent: 0,
                  twisty: Icon(
                    Icons.schedule,
                    size: 10,
                    color: AppColors.text4,
                  ),
                  name: '${t.schema}.${t.name}',
                  active: t.qualifiedName == activeId,
                  onTap: () => state.openTable(t),
                  onSecondaryTapDown: (d) =>
                      _openTableMenu(context, state, t, d.globalPosition),
                ),
            ],
          ),
        if (saved.isNotEmpty)
          _Section(
            label: 'Saved queries',
            count: saved.length,
            children: [
              for (final q in saved)
                _SavedQueryRow(
                  query: q,
                  active: q.id == activeQueryId,
                  state: state,
                ),
            ],
          ),
        _Section(
          label: 'Schemas',
          count: schemas.length,
          children: [
            for (final s in schemas)
              _SchemaBlock(
                schema: s,
                state: state,
                activeId: activeId,
                expanded: state.isSchemaExpanded(s.name),
              ),
          ],
        ),
      ],
    );
  }

  String? _activeTableQualifiedName(AppState state) {
    final tab = state.activeTab;
    if (tab is TableTab) return tab.table.qualifiedName;
    if (tab is SchemaTab) return tab.table.qualifiedName;
    return null;
  }

  String? _activeQueryId(AppState state) {
    final tab = state.activeTab;
    return tab is QueryTab ? tab.id : null;
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.count,
    required this.children,
  });

  final String label;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: AppTheme.ui(
                    size: 10,
                    color: AppColors.textMuted,
                    weight: FontWeight.w600,
                    letterSpacing: 0.06 * 10,
                  ),
                ),
              ),
              Text(
                '$count',
                style: AppTheme.mono(size: 10, color: AppColors.text4),
              ),
            ],
          ),
        ),
        ...children,
      ],
    );
  }
}

/// Eyebrow rule inside a schema separating tables / views / functions.
/// Mirrors the design's inline style: `padding:'4px 0 2px 24px'`, mono 9.5,
/// uppercase letter-spacing 0.06em, text-4.
class _SubEyebrow extends StatelessWidget {
  const _SubEyebrow({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, top: 4, bottom: 2),
      child: Text(
        '$label · $count',
        style: AppTheme.mono(
          size: 9.5,
          color: AppColors.text4,
          weight: FontWeight.w600,
        ).copyWith(letterSpacing: 0.06 * 9.5),
      ),
    );
  }
}

class _SchemaBlock extends StatelessWidget {
  const _SchemaBlock({
    required this.schema,
    required this.state,
    required this.activeId,
    required this.expanded,
  });

  final DbSchema schema;
  final AppState state;
  final String? activeId;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final tables = schema.tables
        .where((t) => t.kind == DbRelationKind.table)
        .toList();
    final views = schema.tables
        .where((t) => t.kind == DbRelationKind.view)
        .toList();
    final matViews = schema.tables
        .where((t) => t.kind == DbRelationKind.materializedView)
        .toList();
    final total = tables.length + views.length + matViews.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TreeRow(
          indent: 0,
          twisty: Icon(
            expanded ? Icons.expand_more : Icons.chevron_right,
            size: 12,
            color: AppColors.text4,
          ),
          icon: Icon(
            Icons.folder_outlined,
            size: 11,
            color: AppColors.textMuted,
          ),
          name: schema.name,
          meta: '$total',
          onTap: () => state.toggleSchema(schema.name),
        ),
        if (expanded) ...[
          if (tables.isNotEmpty) ...[
            _SubEyebrow(label: 'tables', count: tables.length),
            for (final t in tables)
              _TreeRow(
                indent: 1,
                icon: TableGlyph(size: 11, color: AppColors.textMuted),
                name: t.name,
                active: t.qualifiedName == activeId,
                onTap: () => state.openTable(t),
                onSecondaryTapDown: (d) =>
                    _openTableMenu(context, state, t, d.globalPosition),
              ),
          ],
          if (views.isNotEmpty) ...[
            _SubEyebrow(label: 'views', count: views.length),
            for (final v in views)
              _TreeRow(
                indent: 1,
                icon: Icon(
                  Icons.visibility_outlined,
                  size: 11,
                  color: AppColors.info,
                ),
                name: v.name,
                active: v.qualifiedName == activeId,
                onTap: () => state.openTable(v),
                onSecondaryTapDown: (d) =>
                    _openTableMenu(context, state, v, d.globalPosition),
              ),
          ],
          if (matViews.isNotEmpty) ...[
            _SubEyebrow(label: 'materialized views', count: matViews.length),
            for (final v in matViews)
              _TreeRow(
                indent: 1,
                icon: Icon(
                  Icons.layers_outlined,
                  size: 11,
                  color: AppColors.info,
                ),
                name: v.name,
                active: v.qualifiedName == activeId,
                onTap: () => state.openTable(v),
                onSecondaryTapDown: (d) =>
                    _openTableMenu(context, state, v, d.globalPosition),
              ),
          ],
        ],
      ],
    );
  }
}

// --- tree row -------------------------------------------------------------

class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.name,
    this.indent = 0,
    this.twisty,
    this.icon,
    this.meta,
    this.active = false,
    this.onTap,
    this.onSecondaryTapDown,
  });

  final String name;
  final int indent;
  final Widget? twisty;
  final Widget? icon;
  final String? meta;
  final bool active;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    // indent levels: 0 → 6px left, 1 → 18px, 2 → 30px (matching design).
    final leftBase = 6.0 + indent * 12.0;
    return Hoverable(
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTapDown,
      builder: (context, hovering) {
        final Color rowBg = active
            ? AppColors.sidebarRowActive
            : (hovering ? AppColors.sidebarRowHover : Colors.transparent);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: AppLayout.treeRowHeight,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: EdgeInsets.only(left: leftBase, right: 8),
              decoration: BoxDecoration(color: rowBg, borderRadius: Radii.brSm),
              child: Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: Center(child: twisty ?? const SizedBox.shrink()),
                  ),
                  if (icon != null) ...[
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: Center(child: icon!),
                    ),
                  ],
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.mono(
                        size: 11.5,
                        color: active
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        weight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (meta != null)
                    Text(
                      meta!,
                      style: AppTheme.mono(size: 10.5, color: AppColors.text4),
                    ),
                ],
              ),
            ),
            if (active)
              Positioned(
                left: 0,
                top: 4,
                bottom: 4,
                child: Container(
                  width: 2,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// --- saved query row ------------------------------------------------------

class _SavedQueryRow extends StatefulWidget {
  const _SavedQueryRow({
    required this.query,
    required this.active,
    required this.state,
  });

  final SavedQuery query;
  final bool active;
  final AppState state;

  @override
  State<_SavedQueryRow> createState() => _SavedQueryRowState();
}

class _SavedQueryRowState extends State<_SavedQueryRow> {
  void _openMenu(Offset position) {
    final query = widget.query;
    void copy(String text) => Clipboard.setData(ClipboardData(text: text));

    showContextMenu(
      context,
      globalPosition: position,
      entries: [
        CmItem(
          icon: Icons.north_east,
          label: 'Open',
          onTap: () => widget.state.openSavedQuery(query),
        ),
        CmItem(
          icon: Icons.edit_outlined,
          label: 'Rename…',
          onTap: () => _renameDialog(),
        ),
        CmItem(
          icon: Icons.content_copy,
          label: 'Duplicate',
          onTap: () => widget.state.duplicateSavedQuery(query.id),
        ),
        const CmDivider(),
        CmItem(
          icon: Icons.code,
          label: 'Copy SQL',
          onTap: () => copy(query.sql),
        ),
        const CmDivider(),
        CmItem(
          icon: Icons.delete_outline,
          label: 'Delete',
          danger: true,
          onTap: () => widget.state.deleteSavedQuery(query.id),
        ),
      ],
    );
  }

  Future<void> _renameDialog() async {
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameQueryDialog(initial: widget.query.name),
    );
    if (next != null && next.trim().isNotEmpty) {
      widget.state.renameQuery(widget.query.id, next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ts = widget.query.updatedAt;
    return _TreeRow(
      indent: 0,
      twisty: Icon(
        Icons.description_outlined,
        size: 10,
        color: AppColors.text4,
      ),
      name: widget.query.name,
      meta: ts == null ? null : timeAgo(ts),
      active: widget.active,
      onTap: () => widget.state.openSavedQuery(widget.query),
      onSecondaryTapDown: (d) => _openMenu(d.globalPosition),
    );
  }
}

// --- footer ---------------------------------------------------------------

class _FooterStatus extends StatelessWidget {
  const _FooterStatus({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final connected = state.status == ConnectionStatus.connected;
    final color = connected ? AppColors.success : AppColors.textMuted;
    final label = switch (state.status) {
      ConnectionStatus.connected => 'connected',
      ConnectionStatus.connecting => 'connecting…',
      ConnectionStatus.lost => 'connection lost',
      ConnectionStatus.error => 'error',
      ConnectionStatus.disconnected => 'disconnected',
    };
    // Heights / bg match the workspace's pagination bar so the two surfaces
    // form one continuous bottom rail across the app (per the design's
    // single `.pagebar` / sidebar footer pair).
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.24),
                  blurRadius: 0,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTheme.mono(size: 10, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

// --- context menu helper --------------------------------------------------

void _openTableMenu(
  BuildContext context,
  AppState state,
  DbTable table,
  Offset position,
) {
  final qualified = '"${table.schema}"."${table.name}"';
  final isFav = state.isFavorite(table);

  void copy(String value) => Clipboard.setData(ClipboardData(text: value));

  showContextMenu(
    context,
    globalPosition: position,
    entries: [
      CmItem(
        icon: Icons.north_east,
        label: 'Open data',
        onTap: () => state.openTable(table),
      ),
      CmItem(
        icon: Icons.data_object,
        label: 'Show schema (CREATE TABLE)',
        onTap: () => state.openSchema(table),
      ),
      const CmDivider(),
      CmItem(
        icon: isFav ? Icons.star : Icons.star_outline,
        label: isFav ? 'Remove from favourites' : 'Add to favourites',
        onTap: () => state.toggleFavorite(table),
      ),
      const CmDivider(),
      CmItem(
        icon: Icons.label_outline,
        label: 'Copy name',
        onTap: () => copy(table.name),
      ),
      CmItem(
        icon: Icons.tag,
        label: 'Copy qualified name',
        onTap: () => copy(qualified),
      ),
      CmItem(
        icon: Icons.code,
        label: 'Copy SELECT *',
        onTap: () => copy('SELECT * FROM $qualified;'),
      ),
      const CmDivider(),
      CmItem(
        icon: Icons.refresh,
        label: 'Refresh catalog',
        onTap: () => state.refreshCatalog(),
      ),
    ],
  );
}

// --- no-connection list (unchanged style; only shows when disconnected) ---

class _AllConnectionsList extends StatelessWidget {
  const _AllConnectionsList({required this.state});

  final AppState state;

  Future<void> _newConnection(BuildContext context) async {
    final config = await showConnectionDialog(context);
    if (config == null) return;
    state.addConnection(config);
    await state.connect(config);
  }

  @override
  Widget build(BuildContext context) {
    final list = state.connections;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'SAVED',
                  style: AppTheme.ui(
                    size: 10,
                    color: AppColors.textMuted,
                    weight: FontWeight.w600,
                    letterSpacing: 0.06 * 10,
                  ),
                ),
              ),
              Text(
                '${list.length}',
                style: AppTheme.mono(size: 10, color: AppColors.text4),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No saved connections yet.',
                    style: AppTheme.ui(size: 12, color: AppColors.textMuted),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: list.length,
                  itemBuilder: (_, i) =>
                      _SavedConnectionRow(config: list[i], state: state),
                ),
        ),
        Divider(height: 1, color: AppColors.hairline),
        Hoverable(
          onTap: () => _newConnection(context),
          builder: (context, hovering) => Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            color: hovering ? AppColors.sidebarRowHover : Colors.transparent,
            alignment: Alignment.centerLeft,
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
    );
  }
}

class _SavedConnectionRow extends StatelessWidget {
  const _SavedConnectionRow({required this.config, required this.state});

  final ConnectionConfig config;
  final AppState state;

  Future<void> _edit(BuildContext context) async {
    final updated = await showConnectionDialog(context, existing: config);
    if (updated != null) state.updateConnection(updated);
  }

  void _delete() => state.removeConnection(config.id);

  @override
  Widget build(BuildContext context) {
    final ts = config.lastConnectedAt;
    return Hoverable(
      onTap: () => state.connect(config),
      builder: (context, hovering) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        color: hovering ? AppColors.sidebarRowHover : Colors.transparent,
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 9),
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
                      weight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    ts == null ? config.summary : timeAgo(ts),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.mono(size: 10, color: AppColors.textMuted),
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
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(icon, size: 12, color: AppColors.textMuted),
      ),
    );
  }
}

/// Owns the [TextEditingController] inside the rename dialog. Keeping the
/// controller in a [State.dispose] frees it after Flutter has fully torn
/// down the dialog's subtree — disposing it inline after [showDialog]
/// returned would race the closing animation's last `didUpdateWidget`
/// pass and trip "used after being disposed".
class _RenameQueryDialog extends StatefulWidget {
  const _RenameQueryDialog({required this.initial});

  final String initial;

  @override
  State<_RenameQueryDialog> createState() => _RenameQueryDialogState();
}

class _RenameQueryDialogState extends State<_RenameQueryDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.brLg,
        side: BorderSide(color: AppColors.borderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Rename query',
                style: AppTheme.ui(size: 13.5, weight: FontWeight.w600),
              ),
              const SizedBox(height: Insets.md),
              TextField(
                controller: _controller,
                autofocus: true,
                cursorColor: AppColors.accent,
                style: AppTheme.ui(size: 13),
                onSubmitted: (v) => Navigator.of(context).pop(v),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.bg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: Radii.brSm,
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: Radii.brSm,
                    borderSide: BorderSide(color: AppColors.accent),
                  ),
                ),
              ),
              const SizedBox(height: Insets.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: Insets.sm),
                  AppButton(
                    label: 'Rename',
                    icon: Icons.check,
                    primary: true,
                    onPressed: () =>
                        Navigator.of(context).pop(_controller.text),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
