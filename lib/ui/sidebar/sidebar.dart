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

/// Sidebar v2.
///
/// Three regions, top to bottom:
///   1. Connection status row (no controls — the toolbar dropdown is the
///      single switcher).
///   2. Search field — focused with ⌘F, type-filters tables.
///   3. Scrollable list:  RECENT  ·  TABLES (grouped by schema, collapsible).
///
/// Single-schema databases collapse the schema header automatically so the
/// sidebar reads as a flat table list.
class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Container(
      width: 268,
      color: AppColors.sidebarTint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 6),
          _ConnectionRow(state: state),
          if (state.status == ConnectionStatus.connected) ...[
            _SearchField(state: state),
            Divider(height: 1, color: AppColors.border),
            Expanded(child: _Body(state: state)),
          ] else
            Expanded(child: _AllConnectionsList(state: state)),
        ],
      ),
    );
  }
}

// --- Connection row ----------------------------------------------------

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final conn = state.activeConnection;
    final (Color dot, String label, String? sub) = switch (state.status) {
      ConnectionStatus.connected => (
          AppColors.success,
          conn?.name ?? 'Connected',
          conn?.summary,
        ),
      ConnectionStatus.connecting => (AppColors.accent, 'Connecting…', null),
      ConnectionStatus.lost => (
          AppColors.warning,
          conn != null ? '${conn.name} — lost' : 'Connection lost',
          state.connectionError ?? 'Click reconnect in the banner',
        ),
      ConnectionStatus.error => (
          AppColors.error,
          'Connection failed',
          state.connectionError,
        ),
      ConnectionStatus.disconnected => (
          AppColors.textMuted,
          'No connection',
          'Use the toolbar to connect',
        ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.ui(
                    size: 12.5,
                    color: AppColors.textPrimary,
                    weight: FontWeight.w600,
                  ),
                ),
                if (sub != null)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.mono(size: 10, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
          if (state.status == ConnectionStatus.connected)
            IconAction(
              icon: Icons.refresh,
              tooltip: 'Refresh catalog',
              busy: state.isCatalogLoading,
              onPressed: state.isCatalogLoading ? null : state.refreshCatalog,
            ),
        ],
      ),
    );
  }
}

// --- Search ------------------------------------------------------------

class _SearchField extends StatefulWidget {
  const _SearchField({required this.state});
  final AppState state;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.state.sidebarSearch);
    _focus = FocusNode()
      ..addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: _focused
              ? AppColors.bg
              : AppColors.bg.withValues(alpha: 0.5),
          borderRadius: Radii.brSm,
          border: Border.all(
            color: _focused ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search,
              size: 12,
              color: _focused ? AppColors.accent : AppColors.textMuted,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                onChanged: (v) {
                  widget.state.setSidebarSearch(v);
                  setState(() {});
                },
                cursorColor: AppColors.accent,
                cursorHeight: 13,
                style: AppTheme.mono(size: 11.5),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'filter tables',
                  hintStyle:
                      AppTheme.mono(size: 11.5, color: AppColors.textMuted),
                ),
              ),
            ),
            if (hasText)
              GestureDetector(
                onTap: () {
                  _controller.clear();
                  widget.state.setSidebarSearch('');
                  setState(() {});
                },
                child: Icon(
                  Icons.close,
                  size: 12,
                  color: AppColors.textMuted,
                ),
              )
            else
              Text(
                '⌘F',
                style: AppTheme.mono(size: 9.5, color: AppColors.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

// --- Body --------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final query = state.sidebarSearch.trim().toLowerCase();
    final filtering = query.isNotEmpty;

    if (state.schemas.isEmpty) {
      return _Empty(
        text: 'No user tables found.',
      );
    }

    // Filter schemas/tables by query.
    final filteredSchemas = <DbSchema>[];
    for (final s in state.schemas) {
      final visibleTables = filtering
          ? s.tables
              .where((t) => t.name.toLowerCase().contains(query))
              .toList()
          : s.tables;
      if (filtering && visibleTables.isEmpty) continue;
      filteredSchemas.add(DbSchema(name: s.name, tables: visibleTables));
    }

    if (filteredSchemas.isEmpty) {
      return _Empty(text: 'No tables match "$query".');
    }

    final totalTables =
        filteredSchemas.fold<int>(0, (sum, s) => sum + s.tables.length);
    final singleSchema = filteredSchemas.length == 1;
    final activeId = _activeTableQualifiedName(state);

    final favorites = state.favoriteTables;
    final favKeys = {for (final t in favorites) t.qualifiedKey};
    final recents = state.recents
        .where((t) => !favKeys.contains(t.qualifiedKey))
        .toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        if (favorites.isNotEmpty && !filtering) ...[
          _SectionLabel(label: 'Favourites', count: favorites.length),
          for (final t in favorites)
            _TableRow(
              table: t,
              active: t.qualifiedName == activeId,
              onTap: () => state.openTable(t),
              indent: 12,
            ),
          const SizedBox(height: 10),
        ],
        if (recents.isNotEmpty && !filtering) ...[
          _SectionLabel(label: 'Recent', count: recents.length),
          for (final t in recents.take(6))
            _TableRow(
              table: t,
              active: t.qualifiedName == activeId,
              onTap: () => state.openTable(t),
              indent: 12,
            ),
          const SizedBox(height: 10),
        ],
        if (state.savedQueries.isNotEmpty && !filtering) ...[
          _SectionLabel(
            label: 'Queries',
            count: state.savedQueries.length,
          ),
          for (final q in state.savedQueries)
            _SavedQueryRow(
              query: q,
              active: state.activeTab?.id == q.id,
              state: state,
            ),
          const SizedBox(height: 10),
        ],
        _SectionLabel(label: 'Tables', count: totalTables),
        for (final s in filteredSchemas)
          singleSchema
              ? _SchemaBlock(
                  schema: s,
                  state: state,
                  activeId: activeId,
                  collapsible: false,
                )
              : _SchemaBlock(
                  schema: s,
                  state: state,
                  activeId: activeId,
                  collapsible: true,
                  forceExpanded: filtering,
                ),
      ],
    );
  }

  String? _activeTableQualifiedName(AppState state) {
    final tab = state.activeTab;
    if (tab is TableTab) return tab.table.qualifiedName;
    return null;
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        text,
        style: AppTheme.ui(
          size: 12,
          color: AppColors.textMuted,
          weight: FontWeight.w400,
        ),
      ),
    );
  }
}

/// Sidebar contents when no connection is live — list of every saved
/// connection, click to connect, plus a New-connection action at the bottom.
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
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 6),
          child: Row(
            children: [
              Text('Saved'.toUpperCase(), style: AppTheme.eyebrow()),
              const Spacer(),
              Text(
                '${list.length}',
                style: AppTheme.mono(size: 10, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? _Empty(text: 'No saved connections yet.')
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _SavedConnectionRow(
                    config: list[i],
                    state: state,
                  ),
                ),
        ),
        Divider(height: 1, color: AppColors.border),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => _newConnection(context),
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 14),
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
                    style: AppTheme.mono(
                      size: 10,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (hovering) ...[
              _MiniIcon(
                icon: Icons.edit_outlined,
                onTap: () => _edit(context),
              ),
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

// --- Section + Schema --------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, this.count});
  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 6),
      child: Row(
        children: [
          Text(label.toUpperCase(), style: AppTheme.eyebrow()),
          const Spacer(),
          if (count != null)
            Text(
              '$count',
              style: AppTheme.mono(size: 10, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}

class _SchemaBlock extends StatelessWidget {
  const _SchemaBlock({
    required this.schema,
    required this.state,
    required this.activeId,
    required this.collapsible,
    this.forceExpanded = false,
  });

  final DbSchema schema;
  final AppState state;
  final String? activeId;
  final bool collapsible;
  final bool forceExpanded;

  @override
  Widget build(BuildContext context) {
    final expanded = !collapsible ||
        forceExpanded ||
        state.isSchemaExpanded(schema.name);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (collapsible)
          _SchemaHeader(
            schema: schema,
            expanded: expanded,
            onTap: () => state.toggleSchema(schema.name),
          ),
        if (expanded)
          for (final t in schema.tables)
            _TableRow(
              table: t,
              active: t.qualifiedName == activeId,
              onTap: () => state.openTable(t),
              indent: collapsible ? 28 : 12,
            ),
      ],
    );
  }
}

class _SchemaHeader extends StatelessWidget {
  const _SchemaHeader({
    required this.schema,
    required this.expanded,
    required this.onTap,
  });

  final DbSchema schema;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => Container(
        height: 26,
        color: hovering ? AppColors.sidebarRowHover : Colors.transparent,
        padding: const EdgeInsets.only(left: 12, right: 12),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.expand_more : Icons.chevron_right,
              size: 14,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                schema.name,
                style: AppTheme.ui(
                  size: 12,
                  color: AppColors.textSecondary,
                  weight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${schema.tables.length}',
              style: AppTheme.mono(size: 10, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Table row ---------------------------------------------------------

class _TableRow extends StatefulWidget {
  const _TableRow({
    required this.table,
    required this.active,
    required this.onTap,
    required this.indent,
  });

  final DbTable table;
  final bool active;
  final VoidCallback onTap;
  final double indent;

  @override
  State<_TableRow> createState() => _TableRowState();
}

class _TableRowState extends State<_TableRow> {
  AppState get _state => context.read<AppState>();

  void _openContextMenu(Offset position) {
    final table = widget.table;
    final qualified = '"${table.schema}"."${table.name}"';
    final isFav = _state.isFavorite(table);

    void copy(String value) =>
        Clipboard.setData(ClipboardData(text: value));

    showContextMenu(
      context,
      globalPosition: position,
      entries: [
        CmItem(
          icon: Icons.north_east,
          label: 'Open data',
          onTap: () => _state.openTable(table),
        ),
        CmItem(
          icon: Icons.data_object,
          label: 'Show schema (CREATE TABLE)',
          onTap: () => _state.openSchema(table),
        ),
        const CmDivider(),
        CmItem(
          icon: isFav ? Icons.star : Icons.star_outline,
          label: isFav ? 'Remove from favourites' : 'Add to favourites',
          onTap: () => _state.toggleFavorite(table),
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
          onTap: () => _state.refreshCatalog(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isView = widget.table.isView;
    final glyphColor = widget.active
        ? AppColors.accent
        : (isView ? AppColors.info : AppColors.textMuted);

    return Hoverable(
      onTap: widget.onTap,
      onSecondaryTapDown: (d) => _openContextMenu(d.globalPosition),
      builder: (context, hovering) => Container(
        height: 28,
        decoration: BoxDecoration(
          color: widget.active
              ? AppColors.sidebarRowActive
              : (hovering ? AppColors.sidebarRowHover : Colors.transparent),
          border: Border(
            left: BorderSide(
              color: widget.active ? AppColors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        padding: EdgeInsets.only(left: widget.indent - 2, right: 8),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: Center(
                child: isView
                    ? Icon(
                        Icons.visibility_outlined,
                        size: 12,
                        color: glyphColor,
                      )
                    : TableGlyph(size: 12, color: glyphColor),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                widget.table.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.ui(
                  size: 12.5,
                  color: widget.active
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  weight: widget.active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (hovering && !widget.active)
              GestureDetector(
                onTapDown: (d) => _openContextMenu(d.globalPosition),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.more_horiz,
                    size: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            if (widget.active)
              Icon(
                Icons.circle,
                size: 5,
                color: AppColors.accent,
              ),
          ],
        ),
      ),
    );
  }
}


/// A clickable saved query row in the sidebar. Right-click for rename /
/// delete / duplicate.
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
    void copy(String text) =>
        Clipboard.setData(ClipboardData(text: text));

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
    final controller = TextEditingController(text: widget.query.name);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
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
                  controller: controller,
                  autofocus: true,
                  cursorColor: AppColors.accent,
                  style: AppTheme.ui(size: 13),
                  onSubmitted: (v) => Navigator.of(ctx).pop(v),
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
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                    const SizedBox(width: Insets.sm),
                    AppButton(
                      label: 'Rename',
                      icon: Icons.check,
                      primary: true,
                      onPressed: () =>
                          Navigator.of(ctx).pop(controller.text),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    controller.dispose();
    if (next != null && next.trim().isNotEmpty) {
      widget.state.renameQuery(widget.query.id, next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    return Hoverable(
      onTap: () => widget.state.openSavedQuery(widget.query),
      onSecondaryTapDown: (d) => _openMenu(d.globalPosition),
      builder: (context, hovering) => Container(
        height: 28,
        decoration: BoxDecoration(
          color: active
              ? AppColors.sidebarRowActive
              : (hovering
                  ? AppColors.sidebarRowHover
                  : Colors.transparent),
          border: Border(
            left: BorderSide(
              color: active ? AppColors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        padding: const EdgeInsets.only(left: 10, right: 8),
        child: Row(
          children: [
            Icon(
              Icons.terminal,
              size: 12,
              color: active ? AppColors.accent : AppColors.textMuted,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                widget.query.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.ui(
                  size: 12.5,
                  color: active
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  weight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (hovering && !active)
              GestureDetector(
                onTapDown: (d) => _openMenu(d.globalPosition),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.more_horiz,
                    size: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
