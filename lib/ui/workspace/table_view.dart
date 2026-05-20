import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/db_object.dart';
import '../../models/order_term.dart';
import '../../models/value_format.dart';
import '../../state/app_state.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../edits/pending_edits_modal.dart';
import '../widgets/common.dart';
import '../widgets/pagebar.dart';
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
          // Body uses `var(--bg)` per the design's `.grid-wrap` rule — the
          // clause bar above is `var(--bg-deep)`, so the hairline between
          // them reads even when the grid hasn't loaded any rows yet.
          child: ColoredBox(
            color: AppColors.bg,
            child: tab.result == null
              ? (tab.loading
                  ? Center(
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
                  // Force non-positioned children (the ResultsGrid) to fill
                  // the available Stack box. Without this, the grid sizes to
                  // its content (28px header + 0-N rows) and leaves the rest
                  // of the body painted in `var(--bg)`, which looked like
                  // bottom padding on the clause bar.
                  fit: StackFit.expand,
                  children: [
                        ResultsGrid(
                          result: tab.result!,
                          editable: !tab.table.isView,
                          edits: tab.edits,
                          widths: tab.columnWidths,
                          onWidthChanged: (col, w) =>
                              state.persistColumnWidth(tab.table, col, w),
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
                          columnMeta: _columnMeta(state),
                          findRowOwner: (col) {
                            final owner = state.findPrimaryKeyOwner(col);
                            // Skip the redundant "Find row in {this table}"
                            // when the PK match is the table we're viewing.
                            if (owner == null ||
                                owner.qualifiedName ==
                                    tab.table.qualifiedName) {
                              return null;
                            }
                            return owner;
                          },
                          onFindRow: (table, col, value) =>
                              state.findRowInTable(table, col, value),
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
        ),
        _PaginationBar(tab: tab, state: state),
      ],
    );
  }

  Map<String, DbColumn>? _columnMeta(AppState state) {
    final cols = state.columnsFor(tab.table);
    if (cols == null) return null;
    return {for (final c in cols) c.name: c};
  }

  void _addFilter(AppState state, String column, Object? value, bool not) {
    state.appendTableFilter(tab, equalityFragment(column, value, not: not));
  }
}

/// Thin animated progress bar overlaid on top of the grid while a page or
/// filter/sort change is being fetched. Keeps the previous rows visible so the
/// view doesn't flash empty between requests.
class _RefreshBar extends StatelessWidget {
  const _RefreshBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
  final FocusNode _selectFocus = FocusNode();
  final FocusNode _filterFocus = FocusNode();
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
    _selectFocus.dispose();
    _filterFocus.dispose();
    _orderFocus.dispose();
    super.dispose();
  }

  void _applySelect() =>
      widget.state.setTableSelect(widget.tab, _select.text.trim());

  void _applyFilter() =>
      widget.state.setTableFilter(widget.tab, _filter.text.trim());

  void _applyOrder() =>
      widget.state.setTableOrder(widget.tab, _order.text.trim());

  // ignore: unused_element
  void _previewEdits() {
    final statements = widget.state.previewEditStatements(widget.tab);
    showPendingEditsModal(
      context,
      statements: statements,
      onApply: widget.tab.applying ? null : _applyEdits,
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

    // Tab-state changes (FK follow → setTableFilter, header click → setOrder,
    // etc.) need to flow back into the input controllers, but only when the
    // user isn't actively typing in that field.
    if (!_selectFocus.hasFocus && _select.text != tab.selectList) {
      _select.text = tab.selectList;
    }
    if (!_filterFocus.hasFocus && _filter.text != tab.filter) {
      _filter.text = tab.filter;
    }
    if (!_orderFocus.hasFocus && _order.text != tab.orderBy) {
      _order.text = tab.orderBy;
    }

    final selectActive =
        tab.selectList.trim().isNotEmpty && tab.selectList.trim() != '*';
    final whereActive = tab.filter.trim().isNotEmpty;
    final orderActive = tab.orderBy.trim().isNotEmpty;

    // Mirror the design's `.tab-content` grid — the clause bar sits flush
    // against the tab strip, no inline action strip. Refresh / Export /
    // Apply-edits live in the toolbar (and pending edits modal) instead.
    return _ClauseBar(
      selectController: _select,
      filterController: _filter,
      orderController: _order,
      selectFocus: _selectFocus,
      filterFocus: _filterFocus,
      orderFocus: _orderFocus,
      onApplySelect: _applySelect,
      onApplyFilter: _applyFilter,
      onApplyOrder: _applyOrder,
      selectActive: selectActive,
      whereActive: whereActive,
      orderActive: orderActive,
    );
  }
}

/// a trailing action icon.
class _ClauseBar extends StatelessWidget {
  const _ClauseBar({
    required this.selectController,
    required this.filterController,
    required this.orderController,
    required this.selectFocus,
    required this.filterFocus,
    required this.orderFocus,
    required this.onApplySelect,
    required this.onApplyFilter,
    required this.onApplyOrder,
    required this.selectActive,
    required this.whereActive,
    required this.orderActive,
  });

  final SqlHighlightController selectController;
  final SqlHighlightController filterController;
  final SqlHighlightController orderController;
  final FocusNode selectFocus;
  final FocusNode filterFocus;
  final FocusNode orderFocus;
  final VoidCallback onApplySelect;
  final VoidCallback onApplyFilter;
  final VoidCallback onApplyOrder;
  final bool selectActive;
  final bool whereActive;
  final bool orderActive;

  @override
  Widget build(BuildContext context) {
    // The clause bar is exactly 78px tall (three 26px rows) plus the 1px
    // bottom border — no IntrinsicHeight needed because each row is hard-
    // sized, and the side strip stretches via the Row's stretch alignment.
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        height: 78,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left decorative strip — 18px wide, accent gradient.
            Container(
              width: 18,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.accent.withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                ),
                border: Border(
                  right: BorderSide(color: AppColors.hairline),
                ),
              ),
            ),
            // Clause rows stacked vertically.
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ClauseRow(
                    label: 'WHERE',
                    controller: filterController,
                    focusNode: filterFocus,
                    onApply: onApplyFilter,
                    hint: "e.g.  status = 'active'",
                    active: whereActive,
                    actionIcon: Icons.filter_alt_outlined,
                    actionTooltip: 'Apply filter (↵)',
                    isLast: false,
                  ),
                  _ClauseRow(
                    label: 'SELECT',
                    controller: selectController,
                    focusNode: selectFocus,
                    onApply: onApplySelect,
                    hint: '*  or  col_a, col_b',
                    active: selectActive,
                    actionIcon: Icons.view_column_outlined,
                    actionTooltip: 'Apply columns (↵)',
                    isLast: false,
                  ),
                  _ClauseRow(
                    label: 'ORDER',
                    controller: orderController,
                    focusNode: orderFocus,
                    onApply: onApplyOrder,
                    hint: 'click a column header',
                    active: orderActive,
                    actionIcon: Icons.swap_vert,
                    actionTooltip: 'Apply sort (↵)',
                    isLast: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single row inside the clause bar: label | input | icon.
class _ClauseRow extends StatefulWidget {
  const _ClauseRow({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.onApply,
    required this.hint,
    required this.active,
    required this.actionIcon,
    required this.actionTooltip,
    required this.isLast,
  });

  final String label;
  final SqlHighlightController controller;
  final FocusNode focusNode;
  final VoidCallback onApply;
  final String hint;
  final bool active;
  final IconData actionIcon;
  final String actionTooltip;
  /// Omits the bottom hairline on the last row (the outer bar border covers it).
  final bool isLast;

  @override
  State<_ClauseRow> createState() => _ClauseRowState();
}

class _ClauseRowState extends State<_ClauseRow> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labelColor = (_focused || widget.active)
        ? AppColors.accent
        : AppColors.textMuted;

    return Container(
      // Each clause row is exactly 26px tall — the design's `.clause-row`
      // `min-height: 26px`. Using a hard height keeps the TextField inside
      // from inflating the row above the design's three-row 78px clause bar.
      height: 26,
      decoration: BoxDecoration(
        border: widget.isLast
            ? null
            : Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── label ──
          Container(
            width: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.transparent,
                  AppColors.accent.withValues(alpha: 0.04),
                ],
              ),
              border: Border(right: BorderSide(color: AppColors.hairline)),
            ),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 12, right: 10),
            child: Text(
              widget.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: AppTheme.mono(
                size: 10.5,
                color: labelColor,
                weight: FontWeight.w600,
              ).copyWith(letterSpacing: 0.04 * 10.5),
            ),
          ),
          // ── input ──
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter):
                    widget.onApply,
              },
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  cursorColor: AppColors.accent,
                  cursorHeight: 12,
                  style: AppTheme.mono(
                    size: 11.5,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    hintText: widget.hint,
                    hintStyle: AppTheme.mono(
                      size: 11.5,
                      color: AppColors.text4,
                    ).copyWith(fontStyle: FontStyle.italic),
                  ),
                ),
              ),
            ),
          ),
          // ── action icon ──
          Tooltip(
            message: widget.actionTooltip,
            child: Hoverable(
              cursor: SystemMouseCursors.click,
              onTap: widget.onApply,
              builder: (context, hovering) => AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hovering
                      ? AppColors.surfaceHover
                      : Colors.transparent,
                  border: Border(
                    left: BorderSide(color: AppColors.hairline),
                  ),
                ),
                child: Icon(
                  widget.actionIcon,
                  size: 13,
                  color: widget.active
                      ? AppColors.accent
                      : AppColors.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom rail in the design layout — `X rows · page X/Y · N,NNN total ·
/// Xms · refreshed HH:MM:SS` on the left, then pending · refresh + auto
/// dropdown · prev/next on the right. Mono throughout, dot separators,
/// bgDeep surface.
class _PaginationBar extends StatelessWidget {
  const _PaginationBar({required this.tab, required this.state});

  final TableTab tab;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final canPrev = tab.page > 0 && !tab.loading;
    final canNext = tab.page < tab.pageCount - 1 && !tab.loading;
    final result = tab.result;
    final rowCount = result?.rows.length ?? 0;
    final pageCount = tab.pageCount;
    final pendingCount = tab.edits.length;
    final refreshedAt = tab.lastRefreshedAt;

    return Container(
      height: pagebarHeight,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          PbStat(
            head: withCommas(rowCount),
            tail: ' rows',
            headHighlight: true,
          ),
          const PbDot(),
          PbStat(
            head: 'page ',
            mid: '${tab.page + 1}',
            tail: ' / ${withCommas(pageCount)}',
          ),
          const PbDot(),
          PbStat(
            head: withCommas(tab.totalRows),
            tail: ' total',
            headHighlight: true,
          ),
          if (result != null) ...[
            const PbDot(),
            Text(
              '${result.elapsed.inMilliseconds}ms',
              style: AppTheme.mono(
                size: 10.5,
                color: AppColors.textMuted,
              ),
            ),
          ],
          if (refreshedAt != null) ...[
            const PbDot(),
            PbStat(
              head: 'refreshed ',
              mid: formatPagebarClock(refreshedAt),
            ),
          ],
          const Spacer(),
          if (pendingCount > 0) ...[
            _PendingChip(
              count: pendingCount,
              onTap: () {
                final statements = state.previewEditStatements(tab);
                showPendingEditsModal(context, statements: statements);
              },
            ),
            const PbDot(),
          ],
          RefreshDropdown(
            interval: tab.autoRefreshInterval,
            busy: tab.loading,
            canRefresh: !tab.loading,
            onManualRefresh: () => state.refreshTable(tab),
            onSetInterval: (d) => state.setTableAutoRefresh(tab, d),
          ),
          const PbDot(),
          PbChev(
            icon: Icons.chevron_left,
            tooltip: 'Previous page',
            onPressed: canPrev
                ? () => state.loadTablePage(tab, tab.page - 1)
                : null,
          ),
          PbChev(
            icon: Icons.chevron_right,
            tooltip: 'Next page',
            onPressed: canNext
                ? () => state.loadTablePage(tab, tab.page + 1)
                : null,
          ),
        ],
      ),
    );
  }
}


class _PendingChip extends StatelessWidget {
  const _PendingChip({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: hovering ? AppColors.accentSoft : Colors.transparent,
          borderRadius: Radii.brSm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count pending edit${count == 1 ? '' : 's'}',
              style: AppTheme.mono(
                size: 11,
                color: AppColors.accent,
                weight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
