import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/connection_config.dart';
import '../../models/db_catalog.dart';
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

/// Sidebar v4 — Inter-typeset, search-led, pin-forward.
///
/// Layout (top → bottom):
///   1. Connection hero card — database name, server tag, click to open menu.
///   2. Slim filter input — substring filter applied to every list below.
///   3. Scroll body: Pinned · Recent · Queries · Schemas.
///      Schemas auto-expand when filtering. Pin star is an inline toggle.
///   4. Footer status — pulsing dot + plain-text live-state.
class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';

  late final AppState _state = context.read<AppState>();

  /// The sidebar mirrors connections, the session, the catalog, the
  /// per-connection lists, the open tabs and preferences. Listening to just
  /// those child controllers — rather than `context.watch<AppState>()`,
  /// which fires for all ten — keeps a navigation-history push, an
  /// event-log append, or a passphrase change from rebuilding the whole
  /// schema list.
  late final Listenable _sidebarDeps = Listenable.merge([
    _state.preferences,
    _state.registry,
    _state.session,
    _state.catalog,
    _state.perConnection,
    _state.tabsController,
    _state.ui,
  ]);

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final next = _searchCtrl.text;
    if (next != _query) setState(() => _query = next);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _sidebarDeps,
      builder: (context, _) {
        final state = _state;
        final connected = state.status == ConnectionStatus.connected;

        return Container(
          width: state.preferences.sidebarWidth,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.sidebarTint, AppColors.bgDeep],
              stops: const [0.0, 1.0],
            ),
            border: Border(right: BorderSide(color: AppColors.hairline)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ConnHero(state: state),
              if (connected) ...[
                _SearchBar(controller: _searchCtrl, focusNode: _searchFocus),
                Expanded(
                  child: _Body(
                    state: state,
                    query: _query.trim().toLowerCase(),
                  ),
                ),
              ] else
                Expanded(child: _AllConnectionsList(state: state)),
              _FooterStatus(state: state),
            ],
          ),
        );
      },
    );
  }
}

// --- connection hero ------------------------------------------------------

class _ConnHero extends StatelessWidget {
  const _ConnHero({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final conn = state.activeConnection;
    final connected = state.status == ConnectionStatus.connected;
    final menuEnabled = connected || state.status == ConnectionStatus.lost;
    final tint = AppColors.connectionTint(conn?.color);
    final engineIcon = conn?.engine == DbEngine.sqlite
        ? Icons.insert_drive_file_rounded
        : Icons.dns_rounded;

    final title = switch (state.status) {
      ConnectionStatus.connected => conn?.database ?? 'connected',
      ConnectionStatus.connecting => 'connecting…',
      ConnectionStatus.lost => conn?.database ?? 'lost',
      ConnectionStatus.error => 'connection failed',
      ConnectionStatus.disconnected => 'no connection',
    };

    final subtitleParts = <String>[
      if (conn?.name != null && conn!.name.isNotEmpty) conn.name,
      if (state.serverVersion != null) state.serverVersion!,
    ];
    final subtitle = subtitleParts.isEmpty ? null : subtitleParts.join('  ·  ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      child: Hoverable(
        onTap: menuEnabled
            ? () => _openConnMenu(context, state, _anchorBelow(context))
            : null,
        onSecondaryTapDown: menuEnabled
            ? (d) => _openConnMenu(context, state, d.globalPosition)
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
                      colors: [
                        tint,
                        Color.lerp(tint, Colors.black, 0.3)!,
                      ],
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

// --- search ---------------------------------------------------------------

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.focusNode});

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

// --- body -----------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.query});

  final AppState state;
  final String query;

  @override
  Widget build(BuildContext context) {
    final activeTableId = _activeTableQualifiedName(state);
    final activeQueryId = _activeQueryId(state);
    final favKeys = {for (final t in state.favoriteTables) t.qualifiedKey};
    final filtering = query.isNotEmpty;

    bool tableMatches(DbTable t) =>
        !filtering ||
        t.name.toLowerCase().contains(query) ||
        t.schema.toLowerCase().contains(query);

    final favList = state.favoriteTables.where(tableMatches).toList();
    final frequent = filtering
        ? <DbTable>[]
        : state
            .frequentTables(limit: 5 + favKeys.length)
            .where((t) => !favKeys.contains(t.qualifiedKey))
            .take(5)
            .toList();
    final saved = filtering
        ? state.savedQueries
            .where((q) => q.name.toLowerCase().contains(query))
            .toList()
        : state.savedQueries;

    final visibleSchemas = state.schemas.map((s) {
      final tables = filtering
          ? s.tables.where(tableMatches).toList()
          : s.tables;
      return (schema: s, tables: tables);
    }).where((e) => !filtering || e.tables.isNotEmpty).toList();

    final totalTables = state.schemas.fold<int>(
      0,
      (a, b) => a + b.tables.length,
    );

    final empty = favList.isEmpty &&
        frequent.isEmpty &&
        saved.isEmpty &&
        visibleSchemas.isEmpty;

    if (empty && filtering) {
      return _NoResults(query: query);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 16),
      children: [
        if (favList.isNotEmpty)
          _Section(
            label: 'Pinned',
            badge: '${favList.length}',
            children: [
              for (final t in favList)
                _TableRow(
                  table: t,
                  state: state,
                  active: t.qualifiedName == activeTableId,
                  isFav: true,
                  indent: 0,
                  query: query,
                ),
            ],
          ),
        if (frequent.isNotEmpty)
          _Section(
            label: 'Frequent',
            badge: '${frequent.length}',
            children: [
              for (final t in frequent)
                _TableRow(
                  table: t,
                  state: state,
                  active: t.qualifiedName == activeTableId,
                  isFav: favKeys.contains(t.qualifiedKey),
                  indent: 0,
                  query: query,
                ),
            ],
          ),
        if (saved.isNotEmpty)
          _Section(
            label: 'Queries',
            badge: '${saved.length}',
            children: [
              for (final q in saved)
                _SavedQueryRow(
                  query: q,
                  active: q.id == activeQueryId,
                  state: state,
                  match: query,
                ),
            ],
          ),
        _Section(
          label: 'Schemas',
          badge: '$totalTables',
          children: [
            for (final entry in visibleSchemas)
              _SchemaBlock(
                schema: entry.schema,
                tables: entry.tables,
                state: state,
                activeTableId: activeTableId,
                favKeys: favKeys,
                forceExpanded: filtering,
                query: query,
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

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 18,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 8),
          Text(
            'No matches',
            style: AppTheme.ui(
              size: 12.5,
              color: AppColors.textSecondary,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Nothing in this connection matches "$query".',
            style: AppTheme.ui(
              size: 11.5,
              color: AppColors.textMuted,
              weight: FontWeight.w400,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

// --- section --------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.badge,
    required this.children,
  });

  final String label;
  final String badge;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Row(
            children: [
              Text(
                label.toUpperCase(),
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
                  badge,
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
        ...children,
      ],
    );
  }
}

// --- schema block ---------------------------------------------------------

class _SchemaBlock extends StatelessWidget {
  const _SchemaBlock({
    required this.schema,
    required this.tables,
    required this.state,
    required this.activeTableId,
    required this.favKeys,
    required this.forceExpanded,
    required this.query,
  });

  final DbSchema schema;
  final List<DbTable> tables;
  final AppState state;
  final String? activeTableId;
  final Set<String> favKeys;
  final bool forceExpanded;
  final String query;

  @override
  Widget build(BuildContext context) {
    final expanded = forceExpanded || state.isSchemaExpanded(schema.name);
    final tint = AppColors.connectionTint(state.activeConnection?.color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Hoverable(
          onTap: () => state.toggleSchema(schema.name),
          builder: (context, hovering) {
            return Container(
              height: 26,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: hovering
                    ? AppColors.sidebarRowHover
                    : Colors.transparent,
                borderRadius: Radii.brSm,
              ),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: expanded
                          ? tint.withValues(alpha: 0.16)
                          : AppColors.surface,
                      borderRadius: const BorderRadius.all(Radii.xs),
                      border: Border.all(
                        color: expanded
                            ? tint.withValues(alpha: 0.5)
                            : AppColors.borderSoft,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      schema.name.isEmpty
                          ? '?'
                          : schema.name.substring(0, 1).toUpperCase(),
                      style: AppTheme.ui(
                        size: 8.5,
                        color: expanded ? tint : AppColors.textMuted,
                        weight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _HighlightedText(
                      text: schema.name,
                      match: query,
                      style: AppTheme.ui(
                        size: 12,
                        color: AppColors.textSecondary,
                        weight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  Text(
                    '${tables.length}',
                    style: AppTheme.ui(
                      size: 10.5,
                      color: AppColors.text4,
                      weight: FontWeight.w500,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        if (expanded)
          for (final t in tables)
            _TableRow(
              table: t,
              state: state,
              active: t.qualifiedName == activeTableId,
              isFav: favKeys.contains(t.qualifiedKey),
              indent: 1,
              query: query,
              expandable: true,
            ),
      ],
    );
  }
}

// --- table row ------------------------------------------------------------

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.table,
    required this.state,
    required this.active,
    required this.isFav,
    required this.indent,
    required this.query,
    this.expandable = false,
  });

  final DbTable table;
  final AppState state;
  final bool active;
  final bool isFav;
  final int indent;
  final String query;

  /// Schema-tree rows carry a disclosure chevron and expand into a
  /// columns / keys / foreign keys / indexes subtree. Pinned and Frequent
  /// rows are flat shortcuts and stay collapsed.
  final bool expandable;

  @override
  Widget build(BuildContext context) {
    final tint = AppColors.connectionTint(state.activeConnection?.color);
    final expanded = expandable && state.isNodeExpanded(table.qualifiedKey);
    final row = _buildRow(context, tint, expanded);
    if (!expanded) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        _TableDetail(table: table, state: state, indent: indent + 1),
      ],
    );
  }

  Widget _buildRow(BuildContext context, Color tint, bool expanded) {
    final leftBase = 14.0 + indent * 18.0;
    return Hoverable(
      onTap: () => state.openTable(table),
      onSecondaryTapDown: (d) =>
          _openTableMenu(context, state, table, d.globalPosition),
      builder: (context, hovering) {
        final showStar = hovering || isFav;
        final stat = _tableStat(table);
        final rowBg = active
            ? tint.withValues(alpha: 0.13)
            : (hovering ? AppColors.sidebarRowHover : Colors.transparent);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: 24,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: EdgeInsets.only(left: leftBase, right: 6),
              decoration: BoxDecoration(
                color: rowBg,
                borderRadius: Radii.brSm,
              ),
              child: Row(
                children: [
                  if (expandable)
                    _DetailChevron(
                      expanded: expanded,
                      onTap: () => state.toggleNode(table.qualifiedKey),
                    ),
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: Center(child: _kindIcon(table.kind, active, tint)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _HighlightedText(
                      text: table.name,
                      match: query,
                      style: AppTheme.ui(
                        size: 12,
                        color: active
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        weight: active ? FontWeight.w600 : FontWeight.w400,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  if (stat != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      stat,
                      style: AppTheme.mono(
                        size: 9.5,
                        color: AppColors.textSecondary.withValues(alpha: 0.3),
                        weight: FontWeight.w400,
                      ),
                    ),
                  ],
                  if (showStar)
                    _StarToggle(
                      filled: isFav,
                      onTap: () => state.toggleFavorite(table),
                    ),
                ],
              ),
            ),
            if (active)
              Positioned(
                left: 0,
                top: 5,
                bottom: 5,
                child: Container(
                  width: 2.5,
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(2),
                      bottomRight: Radius.circular(2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: tint.withValues(alpha: 0.45),
                        blurRadius: 6,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _kindIcon(DbRelationKind kind, bool active, Color tint) {
    switch (kind) {
      case DbRelationKind.table:
        return TableGlyph(
          size: 12,
          color: active ? tint : AppColors.textMuted,
        );
      case DbRelationKind.view:
        return Icon(
          Icons.visibility_outlined,
          size: 12,
          color: active ? tint : AppColors.info,
        );
      case DbRelationKind.materializedView:
        return Icon(
          Icons.layers_outlined,
          size: 12,
          color: active ? tint : AppColors.info,
        );
    }
  }
}

// --- table detail tree ----------------------------------------------------

/// A right-pointing chevron that rotates to point down when [expanded].
/// When [onTap] is set it claims taps itself (so a chevron inside a row
/// whose body has its own gesture can toggle without triggering it);
/// otherwise it is purely decorative and the enclosing row handles the tap.
class _DetailChevron extends StatelessWidget {
  const _DetailChevron({required this.expanded, this.onTap});

  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = SizedBox(
      width: 18,
      height: 20,
      child: Center(
        child: AnimatedRotation(
          turns: expanded ? 0.25 : 0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Icon(
            Icons.chevron_right_rounded,
            size: 14,
            color: AppColors.textMuted,
          ),
        ),
      ),
    );
    if (onTap == null) return box;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: box,
    );
  }
}

/// The expanded body of a table row: a `columns / keys / foreign keys /
/// indexes` set of collapsible folders, populated from the live catalog.
class _TableDetail extends StatelessWidget {
  const _TableDetail({
    required this.table,
    required this.state,
    required this.indent,
  });

  final DbTable table;
  final AppState state;
  final int indent;

  @override
  Widget build(BuildContext context) {
    final catalog = state.databaseCatalog;
    if (!catalog.hasPhase(CatalogPhase.columns)) {
      return _DetailMessageRow(indent: indent, text: 'Loading details…');
    }

    final tint = AppColors.connectionTint(state.activeConnection?.color);
    final columns = catalog.columnsFor(table);
    final keys = catalog.keysFor(table);
    final foreignKeys = catalog.foreignKeysFor(table);
    final indexes = catalog.indexesFor(table);
    final fkColumns = <String>{
      for (final fk in foreignKeys) ...fk.localColumns,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (columns.isNotEmpty)
          _DetailFolder(
            table: table,
            state: state,
            indent: indent,
            folder: 'columns',
            count: columns.length,
            children: [
              for (final c in columns)
                _DetailLeaf(
                  indent: indent + 1,
                  icon: c.isPrimaryKey
                      ? Icons.key_rounded
                      : (fkColumns.contains(c.name)
                            ? Icons.link_rounded
                            : Icons.crop_landscape),
                  iconColor: c.isPrimaryKey
                      ? tint
                      : (fkColumns.contains(c.name)
                            ? AppColors.info
                            : AppColors.text4),
                  name: c.name,
                  detail: c.dataType,
                ),
            ],
          ),
        if (keys.isNotEmpty)
          _DetailFolder(
            table: table,
            state: state,
            indent: indent,
            folder: 'keys',
            count: keys.length,
            children: [
              for (final k in keys)
                _DetailLeaf(
                  indent: indent + 1,
                  icon: Icons.key_rounded,
                  iconColor: k.isPrimary ? tint : AppColors.textMuted,
                  name: k.name,
                  detail:
                      '(${k.columns.join(', ')})'
                      '${k.isPrimary ? '' : '  ·  UNIQUE'}',
                ),
            ],
          ),
        if (foreignKeys.isNotEmpty)
          _DetailFolder(
            table: table,
            state: state,
            indent: indent,
            folder: 'foreign keys',
            count: foreignKeys.length,
            children: [
              for (final fk in foreignKeys)
                _DetailLeaf(
                  indent: indent + 1,
                  icon: Icons.link_rounded,
                  iconColor: AppColors.info,
                  name: fk.constraintName,
                  detail:
                      '(${fk.localColumns.join(', ')}) → ${fk.refTable}',
                  onTap: () {
                    final ref = catalog.relation(fk.refTableOid);
                    if (ref != null) state.openTable(ref);
                  },
                ),
            ],
          ),
        if (indexes.isNotEmpty)
          _DetailFolder(
            table: table,
            state: state,
            indent: indent,
            folder: 'indexes',
            count: indexes.length,
            children: [
              for (final ix in indexes)
                _DetailLeaf(
                  indent: indent + 1,
                  icon: Icons.bolt_rounded,
                  iconColor: AppColors.textMuted,
                  name: ix.name,
                  detail:
                      '(${ix.columns.join(', ')})'
                      '${ix.unique ? '  ·  UNIQUE' : ''}',
                ),
            ],
          ),
      ],
    );
  }
}

/// One collapsible folder ("columns", "indexes", …) under a table.
class _DetailFolder extends StatelessWidget {
  const _DetailFolder({
    required this.table,
    required this.state,
    required this.indent,
    required this.folder,
    required this.count,
    required this.children,
  });

  final DbTable table;
  final AppState state;
  final int indent;
  final String folder;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final id = '${table.qualifiedKey} $folder';
    final expanded = state.isNodeExpanded(id);
    final leftBase = 14.0 + indent * 18.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Hoverable(
          onTap: () => state.toggleNode(id),
          builder: (context, hovering) {
            return Container(
              height: 24,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: EdgeInsets.only(left: leftBase, right: 6),
              decoration: BoxDecoration(
                color: hovering
                    ? AppColors.sidebarRowHover
                    : Colors.transparent,
                borderRadius: Radii.brSm,
              ),
              child: Row(
                children: [
                  _DetailChevron(expanded: expanded),
                  Icon(
                    Icons.folder_outlined,
                    size: 13,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      folder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.ui(
                        size: 11.5,
                        color: AppColors.textSecondary,
                        weight: FontWeight.w400,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: AppTheme.ui(
                      size: 10,
                      color: AppColors.text4,
                      weight: FontWeight.w500,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        if (expanded) ...children,
      ],
    );
  }
}

/// A leaf in the table tree: one column, key, foreign key or index. Carries
/// an [onTap] only for foreign keys, which navigate to the referenced table.
class _DetailLeaf extends StatelessWidget {
  const _DetailLeaf({
    required this.indent,
    required this.icon,
    required this.iconColor,
    required this.name,
    this.detail,
    this.onTap,
  });

  final int indent;
  final IconData icon;
  final Color iconColor;
  final String name;
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final leftBase = 14.0 + indent * 18.0;
    return Hoverable(
      onTap: onTap,
      cursor: onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      builder: (context, hovering) {
        return Container(
          height: 22,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: EdgeInsets.only(left: leftBase, right: 6),
          decoration: BoxDecoration(
            color: hovering ? AppColors.sidebarRowHover : Colors.transparent,
            borderRadius: Radii.brSm,
          ),
          child: Row(
            children: [
              Icon(icon, size: 12, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.ui(
                          size: 11.5,
                          color: AppColors.textSecondary,
                          weight: FontWeight.w400,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          detail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.mono(
                            size: 9.5,
                            color: AppColors.textMuted,
                            weight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Placeholder row shown while phase-1 introspection is still in flight.
class _DetailMessageRow extends StatelessWidget {
  const _DetailMessageRow({required this.indent, required this.text});

  final int indent;
  final String text;

  @override
  Widget build(BuildContext context) {
    final leftBase = 14.0 + indent * 18.0 + 18.0;
    return Container(
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: EdgeInsets.only(left: leftBase, right: 6),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: AppTheme.ui(
          size: 11,
          color: AppColors.textMuted,
          weight: FontWeight.w400,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

/// Faint "rows / size" suffix for a table row, e.g. `110k / 10GB`. Returns
/// null when the engine reports neither figure.
String? _tableStat(DbTable table) {
  final parts = <String>[
    if (table.rowEstimate != null) _compactCount(table.rowEstimate!),
    if (table.sizeBytes != null) _compactBytes(table.sizeBytes!),
  ];
  return parts.isEmpty ? null : parts.join(' / ');
}

/// Human-friendly row count: `940`, `1.2k`, `110k`, `3.4M`, `2.1B`.
String _compactCount(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) {
    final k = n / 1000;
    return k >= 99.95 ? '${k.round()}k' : '${k.toStringAsFixed(1)}k';
  }
  if (n < 1000000000) {
    final m = n / 1000000;
    return m >= 99.95 ? '${m.round()}M' : '${m.toStringAsFixed(1)}M';
  }
  return '${(n / 1000000000).toStringAsFixed(1)}B';
}

/// Human-friendly byte size: `512B`, `48KB`, `10GB`, `1.4TB`.
String _compactBytes(int bytes) {
  const kb = 1024.0;
  const mb = kb * 1024;
  const gb = mb * 1024;
  const tb = gb * 1024;
  if (bytes < kb) return '${bytes}B';
  if (bytes < mb) return '${(bytes / kb).round()}KB';
  if (bytes < gb) {
    final v = bytes / mb;
    return v >= 99.95 ? '${v.round()}MB' : '${v.toStringAsFixed(1)}MB';
  }
  if (bytes < tb) {
    final v = bytes / gb;
    return v >= 99.95 ? '${v.round()}GB' : '${v.toStringAsFixed(1)}GB';
  }
  return '${(bytes / tb).toStringAsFixed(1)}TB';
}

class _StarToggle extends StatelessWidget {
  const _StarToggle({required this.filled, required this.onTap});

  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) {
        final color = filled
            ? AppColors.warn
            : (hovering ? AppColors.textSecondary : AppColors.text4);
        return Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            filled ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 13,
            color: color,
          ),
        );
      },
    );
  }
}

// --- highlighted text -----------------------------------------------------

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.match,
    required this.style,
  });

  final String text;
  final String match;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (match.isEmpty) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final lower = text.toLowerCase();
    final idx = lower.indexOf(match);
    if (idx < 0) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final before = text.substring(0, idx);
    final hit = text.substring(idx, idx + match.length);
    final after = text.substring(idx + match.length);
    final hitStyle = style.copyWith(
      color: AppColors.accent,
      fontWeight: FontWeight.w700,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: before, style: style),
          TextSpan(text: hit, style: hitStyle),
          TextSpan(text: after, style: style),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// --- saved query row ------------------------------------------------------

class _SavedQueryRow extends StatefulWidget {
  const _SavedQueryRow({
    required this.query,
    required this.active,
    required this.state,
    required this.match,
  });

  final SavedQuery query;
  final bool active;
  final AppState state;
  final String match;

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
          onTap: _renameDialog,
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
    final tint = AppColors.connectionTint(
      widget.state.activeConnection?.color,
    );
    return Hoverable(
      onTap: () => widget.state.openSavedQuery(widget.query),
      onSecondaryTapDown: (d) => _openMenu(d.globalPosition),
      builder: (context, hovering) {
        final bg = widget.active
            ? tint.withValues(alpha: 0.13)
            : (hovering ? AppColors.sidebarRowHover : Colors.transparent);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: 24,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: const EdgeInsets.only(left: 14, right: 6),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: Radii.brSm,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.code_rounded,
                    size: 12,
                    color: widget.active ? tint : AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _HighlightedText(
                      text: widget.query.name,
                      match: widget.match,
                      style: AppTheme.ui(
                        size: 12,
                        color: widget.active
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        weight: widget.active
                            ? FontWeight.w600
                            : FontWeight.w400,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  if (ts != null)
                    Text(
                      timeAgo(ts),
                      style: AppTheme.ui(
                        size: 10,
                        color: AppColors.text4,
                        weight: FontWeight.w400,
                        letterSpacing: 0,
                      ),
                    ),
                ],
              ),
            ),
            if (widget.active)
              Positioned(
                left: 0,
                top: 5,
                bottom: 5,
                child: Container(
                  width: 2.5,
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(2),
                      bottomRight: Radius.circular(2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: tint.withValues(alpha: 0.45),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// --- footer status --------------------------------------------------------

class _FooterStatus extends StatelessWidget {
  const _FooterStatus({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final connected = state.status == ConnectionStatus.connected;
    final color = switch (state.status) {
      ConnectionStatus.connected => AppColors.success,
      ConnectionStatus.connecting => AppColors.warn,
      ConnectionStatus.lost => AppColors.warn,
      ConnectionStatus.error => AppColors.error,
      ConnectionStatus.disconnected => AppColors.textMuted,
    };
    final label = switch (state.status) {
      ConnectionStatus.connected => 'live',
      ConnectionStatus.connecting => 'connecting…',
      ConnectionStatus.lost => 'connection lost',
      ConnectionStatus.error => 'error',
      ConnectionStatus.disconnected => 'offline',
    };

    final tableCount = state.schemas.fold<int>(
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

// --- context menu for tables ---------------------------------------------

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
        onTap: state.refreshCatalog,
      ),
    ],
  );
}

// --- disconnected: saved connections list --------------------------------

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
                      _SavedConnectionRow(config: list[i], state: state),
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
    final tint = AppColors.connectionTint(config.color);
    return Hoverable(
      onTap: () => state.connect(config),
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
