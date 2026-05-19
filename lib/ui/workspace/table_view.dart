import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/order_term.dart';
import '../../models/value_format.dart';
import '../../state/app_state.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../edits/pending_edits_modal.dart';
import '../export/export_dialog.dart';
import '../widgets/common.dart';
import '../widgets/sql_highlight_controller.dart';
import 'results_grid.dart';

/// Data view for a single relation: a toolbar with row filter, sort, and
/// pending-edit actions, the editable row grid, and a pagination footer.
class TableView extends StatelessWidget {
  const TableView({super.key, required this.tab});

  final TableTab tab;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Column(
      children: [
        _TableToolbar(tab: tab, state: state),
        Expanded(
          child: tab.result == null
              ? (tab.loading
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accent,
                        ),
                      ),
                    )
                  : const EmptyState(
                      icon: Icons.warning_amber_outlined,
                      title: 'Could not load data',
                    ))
              : Stack(
                  children: [
                        ResultsGrid(
                          result: tab.result!,
                          editable: !tab.table.isView,
                          edits: tab.edits,
                          widths: tab.columnWidths,
                          onEditCell: (row, col, value) =>
                              state.setCellEdit(tab, row, col, value),
                          onRevertEdit: (row, col) =>
                              state.revertCellEdit(tab, row, col),
                          order: parseOrderBy(tab.orderBy),
                          onSortColumn: (column) =>
                              state.cycleTableOrder(tab, column),
                          onSetSort: (column, desc) =>
                              state.setColumnSort(tab, column, desc),
                          onAddFilter: (column, value, not) =>
                              _addFilter(state, column, value, not),
                          foreignKeys: state.foreignKeysFor(tab.table),
                          onFollowForeignKey: (fk, value) =>
                              state.followForeignKey(fk, value),
                        ),
                        if (tab.loading)
                          const Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: _RefreshBar(),
                          ),
                      ],
                    ),
        ),
        _PaginationBar(tab: tab, state: state),
      ],
    );
  }

  void _addFilter(AppState state, String column, dynamic value, bool not) {
    final String fragment;
    if (value == null) {
      fragment = '"$column" IS ${not ? 'NOT ' : ''}NULL';
    } else if (value is bool || value is num) {
      fragment = '"$column" ${not ? '!=' : '='} $value';
    } else {
      final text = formatCellValue(value) ?? '';
      final escaped = text.replaceAll("'", "''");
      fragment = '"$column" ${not ? '!=' : '='} \'$escaped\'';
    }
    state.appendTableFilter(tab, fragment);
  }
}

/// Thin animated progress bar overlaid on top of the grid while a page or
/// filter/sort change is being fetched. Keeps the previous rows visible so the
/// view doesn't flash empty between requests.
class _RefreshBar extends StatelessWidget {
  const _RefreshBar();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 2,
      child: LinearProgressIndicator(
        minHeight: 2,
        backgroundColor: Colors.transparent,
        valueColor: AlwaysStoppedAnimation(AppColors.accent),
      ),
    );
  }
}

class _TableToolbar extends StatefulWidget {
  const _TableToolbar({required this.tab, required this.state});

  final TableTab tab;
  final AppState state;

  @override
  State<_TableToolbar> createState() => _TableToolbarState();
}

class _TableToolbarState extends State<_TableToolbar> {
  late final SqlHighlightController _select;
  late final SqlHighlightController _filter;
  late final SqlHighlightController _order;
  final FocusNode _orderFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _select = SqlHighlightController(text: widget.tab.selectList);
    _filter = SqlHighlightController(text: widget.tab.filter);
    _order = SqlHighlightController(text: widget.tab.orderBy);
  }

  @override
  void dispose() {
    _select.dispose();
    _filter.dispose();
    _order.dispose();
    _orderFocus.dispose();
    super.dispose();
  }

  void _applySelect() =>
      widget.state.setTableSelect(widget.tab, _select.text.trim());

  void _applyFilter() =>
      widget.state.setTableFilter(widget.tab, _filter.text.trim());

  void _applyOrder() =>
      widget.state.setTableOrder(widget.tab, _order.text.trim());

  void _previewEdits() {
    final statements = widget.state.previewEditStatements(widget.tab);
    showPendingEditsModal(context, statements: statements);
  }

  void _openExport() {
    final tab = widget.tab;
    final result = tab.result;
    if (result == null) return;
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    showExportDialog(
      context,
      target: ExportTarget(
        suggestedFilename: '${tab.table.name}_$timestamp.csv',
        currentResult: result,
        fetchAll: () => widget.state.fetchAllForExport(tab),
        totalRowsForAll: tab.totalRows,
      ),
    );
  }

  Future<void> _applyEdits() async {
    final error = await widget.state.applyTableEdits(widget.tab);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.surfaceAlt,
          content: Text(
            'Apply failed: $error',
            style: AppTheme.mono(size: 11.5, color: AppColors.error),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;

    // Header clicks mutate orderBy directly — mirror it into the field.
    if (!_orderFocus.hasFocus && _order.text != tab.orderBy) {
      _order.text = tab.orderBy;
    }

    final selectActive =
        tab.selectList.trim().isNotEmpty && tab.selectList.trim() != '*';
    final whereActive = tab.filter.trim().isNotEmpty;
    final orderActive = tab.orderBy.trim().isNotEmpty;

    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Insets.md),
      child: Row(
        children: [
          // ── identity ──
          _TableIdentity(tab: tab),
          const _Rail(),
          // ── clauses ──
          Expanded(
            flex: 2,
            child: _Clause(
              prefix: 'SELECT',
              controller: _select,
              onApply: _applySelect,
              hint: '*  or  col_a, col_b',
              active: selectActive,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 4,
            child: _Clause(
              prefix: 'WHERE',
              controller: _filter,
              onApply: _applyFilter,
              hint: "filter — e.g. status = 'active'",
              active: whereActive,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: _Clause(
              prefix: 'ORDER BY',
              controller: _order,
              focusNode: _orderFocus,
              onApply: _applyOrder,
              hint: 'click a column header',
              active: orderActive,
            ),
          ),
          const _Rail(),
          // ── actions ──
          if (!tab.table.isView) ...[
            _EditCountBadge(
              count: tab.edits.length,
              onTap: tab.hasEdits ? () => _previewEdits() : null,
            ),
            if (tab.hasEdits) const SizedBox(width: 6),
            IconAction(
              icon: Icons.undo,
              tooltip: tab.hasEdits
                  ? 'Reset pending edits'
                  : 'No pending edits',
              onPressed: tab.hasEdits && !tab.applying
                  ? () => widget.state.resetTableEdits(tab)
                  : null,
            ),
            const SizedBox(width: 2),
            IconAction(
              icon: Icons.check,
              tooltip: tab.applying
                  ? 'Applying…'
                  : (tab.hasEdits ? 'Apply edits' : 'No pending edits'),
              primary: true,
              busy: tab.applying,
              onPressed: tab.hasEdits && !tab.applying ? _applyEdits : null,
            ),
            const SizedBox(width: 4),
          ],
          IconAction(
            icon: Icons.ios_share,
            tooltip: 'Export…',
            onPressed: tab.result == null ? null : _openExport,
          ),
        ],
      ),
    );
  }
}

/// Schema-qualified table name + relation icon. The schema renders in a quiet
/// muted tone so the eye locks onto the table name itself.
class _TableIdentity extends StatelessWidget {
  const _TableIdentity({required this.tab});
  final TableTab tab;

  @override
  Widget build(BuildContext context) {
    final isView = tab.table.isView;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isView ? Icons.visibility_outlined : Icons.table_rows_outlined,
            size: 14,
            color: isView ? AppColors.info : AppColors.accent,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: AppTheme.mono(size: 12, weight: FontWeight.w600),
                children: [
                  TextSpan(
                    text: '${tab.table.schema}.',
                    style: AppTheme.mono(
                      size: 12,
                      color: AppColors.textMuted,
                      weight: FontWeight.w400,
                    ),
                  ),
                  TextSpan(text: tab.table.name),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A 1px vertical rail that separates toolbar sections.
class _Rail extends StatelessWidget {
  const _Rail();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: AppColors.border,
    );
  }
}

/// A clause chip: uppercase prefix label · vertical hairline · inline value.
/// The prefix is rendered in the accent when the clause is constraining the
/// query, so an "empty" toolbar reads as cleanly as a maxed-out one.
class _Clause extends StatefulWidget {
  const _Clause({
    required this.prefix,
    required this.controller,
    required this.onApply,
    required this.hint,
    required this.active,
    this.focusNode,
  });

  final String prefix;
  final SqlHighlightController controller;
  final VoidCallback onApply;
  final String hint;
  final bool active;
  final FocusNode? focusNode;

  @override
  State<_Clause> createState() => _ClauseState();
}

class _ClauseState extends State<_Clause> {
  late final FocusNode _focus;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? FocusNode();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefixColor = _focused
        ? AppColors.accent
        : (widget.active ? AppColors.accent : AppColors.textMuted);
    final borderColor = _focused
        ? AppColors.accent
        : (widget.active ? AppColors.accent.withValues(alpha: 0.5) : AppColors.border);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: 28,
      decoration: BoxDecoration(
        color: _focused ? AppColors.bg : AppColors.bg.withValues(alpha: 0.6),
        borderRadius: Radii.brSm,
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 9, right: 9),
            child: Text(
              widget.prefix,
              style: AppTheme.ui(
                size: 9.5,
                color: prefixColor,
                weight: FontWeight.w700,
                letterSpacing: 0.9,
              ),
            ),
          ),
          Container(width: 1, height: 28, color: AppColors.border),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): widget.onApply,
              },
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                cursorColor: AppColors.accent,
                cursorHeight: 13,
                style: AppTheme.mono(size: 11.5),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 8,
                  ),
                  hintText: widget.hint,
                  hintStyle:
                      AppTheme.mono(size: 11.5, color: AppColors.textMuted),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Tight pill that signals the count of pending cell edits. Click to preview
/// the generated UPDATE statements.
class _EditCountBadge extends StatefulWidget {
  const _EditCountBadge({required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  State<_EditCountBadge> createState() => _EditCountBadgeState();
}

class _EditCountBadgeState extends State<_EditCountBadge> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    if (widget.count == 0) return const SizedBox.shrink();
    final clickable = widget.onTap != null;
    final tooltip = clickable
        ? '${widget.count} pending edit${widget.count == 1 ? '' : 's'} — click to preview'
        : '${widget.count} pending edit${widget.count == 1 ? '' : 's'}';

    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: clickable
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: _hover && clickable
                  ? AppColors.accent.withValues(alpha: 0.32)
                  : AppColors.accentSoft,
              borderRadius: Radii.brSm,
            ),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '${widget.count}',
                  style: AppTheme.mono(
                    size: 10.5,
                    color: AppColors.accent,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom rail: pagination affordances + a quiet row-count readout.
class _PaginationBar extends StatelessWidget {
  const _PaginationBar({required this.tab, required this.state});

  final TableTab tab;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final canPrev = tab.page > 0 && !tab.loading;
    final canNext = tab.page < tab.pageCount - 1 && !tab.loading;
    final first = tab.totalRows == 0 ? 0 : tab.offset + 1;
    final last = (tab.offset + tab.pageSize).clamp(0, tab.totalRows);

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: Insets.md),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          IconAction(
            icon: Icons.chevron_left,
            tooltip: 'Previous page',
            onPressed:
                canPrev ? () => state.loadTablePage(tab, tab.page - 1) : null,
          ),
          IconAction(
            icon: Icons.chevron_right,
            tooltip: 'Next page',
            onPressed:
                canNext ? () => state.loadTablePage(tab, tab.page + 1) : null,
          ),
          const SizedBox(width: 6),
          RichText(
            text: TextSpan(
              style: AppTheme.mono(size: 10.5, color: AppColors.textMuted),
              children: [
                const TextSpan(text: 'pg '),
                TextSpan(
                  text: '${tab.page + 1}',
                  style: AppTheme.mono(
                    size: 10.5,
                    color: AppColors.textSecondary,
                    weight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: ' / ${tab.pageCount}'),
              ],
            ),
          ),
          const Spacer(),
          RichText(
            text: TextSpan(
              style: AppTheme.mono(size: 10.5, color: AppColors.textMuted),
              children: [
                TextSpan(
                  text: '$first–$last',
                  style: AppTheme.mono(
                    size: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                TextSpan(text: '  of  ${tab.totalRows}  rows'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
