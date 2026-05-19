import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/db_object.dart';
import '../../state/app_state.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';

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
            const Divider(height: 1, color: AppColors.border),
            Expanded(child: _Body(state: state)),
          ] else
            const Expanded(child: _DisconnectedHint()),
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
              tooltip: 'Refresh schema',
              onPressed: state.refreshSchemas,
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
                child: const Icon(
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

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        if (state.recents.isNotEmpty && !filtering) ...[
          _SectionLabel(label: 'Recent', count: state.recents.length),
          for (final t in state.recents.take(6))
            _TableRow(
              table: t,
              active: t.qualifiedName == activeId,
              onTap: () => state.openTable(t),
              indent: 12,
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

class _DisconnectedHint extends StatelessWidget {
  const _DisconnectedHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.bg.withValues(alpha: 0.45),
                borderRadius: Radii.brMd,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.storage_outlined,
                size: 20,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Pick a connection from the toolbar to load the schema.',
              textAlign: TextAlign.center,
              style: AppTheme.ui(
                size: 11.5,
                color: AppColors.textMuted,
                weight: FontWeight.w400,
              ),
            ),
          ],
        ),
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

class _SchemaHeader extends StatefulWidget {
  const _SchemaHeader({
    required this.schema,
    required this.expanded,
    required this.onTap,
  });

  final DbSchema schema;
  final bool expanded;
  final VoidCallback onTap;

  @override
  State<_SchemaHeader> createState() => _SchemaHeaderState();
}

class _SchemaHeaderState extends State<_SchemaHeader> {
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
          height: 26,
          color: _hover ? AppColors.sidebarRowHover : Colors.transparent,
          padding: const EdgeInsets.only(left: 12, right: 12),
          child: Row(
            children: [
              Icon(
                widget.expanded ? Icons.expand_more : Icons.chevron_right,
                size: 14,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  widget.schema.name,
                  style: AppTheme.ui(
                    size: 12,
                    color: AppColors.textSecondary,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${widget.schema.tables.length}',
                style: AppTheme.mono(size: 10, color: AppColors.textMuted),
              ),
            ],
          ),
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
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isView = widget.table.isView;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 26,
          decoration: BoxDecoration(
            color: widget.active
                ? AppColors.sidebarRowActive
                : (_hover ? AppColors.sidebarRowHover : Colors.transparent),
            border: Border(
              left: BorderSide(
                color: widget.active ? AppColors.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          padding: EdgeInsets.only(left: widget.indent - 2, right: 12),
          child: Row(
            children: [
              Icon(
                isView ? Icons.visibility_outlined : Icons.table_rows_outlined,
                size: 12,
                color: widget.active
                    ? AppColors.accent
                    : (isView ? AppColors.info : AppColors.textMuted),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.table.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono(
                    size: 11.5,
                    color: widget.active
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    weight: widget.active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (widget.active)
                const Icon(
                  Icons.circle,
                  size: 5,
                  color: AppColors.accent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

