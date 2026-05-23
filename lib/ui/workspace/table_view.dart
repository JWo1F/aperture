import 'package:flutter/material.dart';

import '../../models/count_format.dart';
import '../../models/db_object.dart';
import '../../models/order_term.dart';
import '../../models/value_format.dart';
import '../../services/sql_complete.dart';
import '../../state/app_globals.dart';
import '../../state/catalog_controller.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../app_shell/toolbar_actions.dart';
import '../widgets/code_editor.dart';
import '../widgets/common.dart';
import '../widgets/pagebar.dart';
import '../widgets/value_selector.dart';
import 'results_grid/results_grid.dart';

/// Data view for a single relation: a toolbar with row filter, sort, and
/// pending-edit actions, the editable row grid, and a pagination footer.
class TableView extends StatelessWidget {
  const TableView({super.key, required this.tab});

  final TableTab tab;

  @override
  Widget build(BuildContext context) {
    // Read controllers non-reactively — the workspace already wraps this
    // widget in a ListenableBuilder(listenable: tab), so tab field changes
    // (result, loading, edits, page, …) drive rebuilds. The whole subtree
    // is then wrapped in a ListenableBuilder on CatalogController so
    // phase-1 column / FK arrivals refresh the toolbar's autocomplete and
    // the grid's typed-cell colouring + FK indicators — without dragging
    // in anything else. readOnly is a connection-level slice selected
    // narrowly.
    final catalog = appState.catalog;
    final tabs = appState.tabsController;
    final store = appState.store;
    final session = appState.session;

    return Selector<bool>(
      listenable: session,
      selector: () => session.activeConnection?.readOnly ?? false,
      builder: (_, readOnly) => ListenableBuilder(
        listenable: catalog,
        builder: (_, _) => Column(
          children: [
            _TableToolbar(tab: tab),
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
                        // Force non-positioned children (the ResultsGrid) to
                        // fill the available Stack box. Without this, the
                        // grid sizes to its content (28px header + 0-N rows)
                        // and leaves the rest of the body painted in
                        // `var(--bg)`, which looked like bottom padding on
                        // the clause bar.
                        fit: StackFit.expand,
                        children: [
                          ResultsGrid(
                            result: tab.result!,
                            editable: !tab.table.isView && !readOnly,
                            edits: tab.edits,
                            deletedRows: tab.deletedRows,
                            inserts: tab.inserts,
                            onDeleteRow: (row) => tabs.deleteRow(tab, row),
                            onRestoreDeletedRow: (row) =>
                                tabs.restoreDeletedRow(tab, row),
                            onDuplicateRow: (row) =>
                                tabs.duplicateRow(tab, row),
                            onAddRow: (row) => tabs.addRow(tab, row),
                            widths: tab.columnWidths,
                            onWidthChanged: (col, w) {
                              final id = session.activeConnection?.id;
                              if (id != null) {
                                store.setColumnWidth(id, tab.table, col, w);
                              }
                            },
                            onEditCell: (row, col, value) =>
                                tabs.setCellEdit(tab, row, col, value),
                            onRevertEdit: (row, col) =>
                                tabs.revertCellEdit(tab, row, col),
                            order: parseOrderBy(tab.orderBy),
                            onSortColumn: (column) =>
                                tabs.cycleTableOrder(tab, column),
                            onSetSort: (column, desc) =>
                                tabs.setColumnSort(tab, column, desc),
                            onAddFilter: (column, value, not) =>
                                _addFilter(column, value, not),
                            foreignKeys: catalog.foreignKeysFor(tab.table),
                            onFollowForeignKey: (fk, value) =>
                                appState.followForeignKey(fk, value),
                            columnMeta: _columnMeta(catalog),
                            findRowOwner: (col) {
                              final owner =
                                  catalog.findPrimaryKeyOwner(col);
                              // Skip the redundant "Find row in {this
                              // table}" when the PK match is the table
                              // we're viewing.
                              if (owner == null ||
                                  owner.qualifiedName ==
                                      tab.table.qualifiedName) {
                                return null;
                              }
                              return owner;
                            },
                            onFindRow: (table, col, value) =>
                                appState.findRowInTable(table, col, value),
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
            _PaginationBar(tab: tab),
          ],
        ),
      ),
    );
  }

  Map<String, DbColumn>? _columnMeta(CatalogController catalog) {
    final cols = catalog.columnsFor(tab.table);
    if (cols == null) return null;
    return {for (final c in cols) c.name: c};
  }

  void _addFilter(String column, Object? value, bool not) {
    appState.tabsController.appendTableFilter(
      tab,
      equalityFragment(column, value, not: not),
    );
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
  const _TableToolbar({required this.tab});

  final TableTab tab;

  @override
  State<_TableToolbar> createState() => _TableToolbarState();
}

class _TableToolbarState extends State<_TableToolbar> {
  late final CodeEditorController _select;
  late final CodeEditorController _filter;
  late final CodeEditorController _order;
  final FocusNode _selectFocus = FocusNode();
  final FocusNode _filterFocus = FocusNode();
  final FocusNode _orderFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _select = CodeEditorController(text: widget.tab.selectList);
    _filter = CodeEditorController(text: widget.tab.filter);
    _order = CodeEditorController(text: widget.tab.orderBy);
    widget.tab.addListener(_onTabChanged);
  }

  @override
  void didUpdateWidget(_TableToolbar old) {
    super.didUpdateWidget(old);
    if (!identical(widget.tab, old.tab)) {
      old.tab.removeListener(_onTabChanged);
      widget.tab.addListener(_onTabChanged);
      _syncFromTab();
    }
  }

  @override
  void dispose() {
    widget.tab.removeListener(_onTabChanged);
    _select.dispose();
    _filter.dispose();
    _order.dispose();
    _selectFocus.dispose();
    _filterFocus.dispose();
    _orderFocus.dispose();
    super.dispose();
  }

  // Tab clause mutations (FK follow, header sort cycle, appendTableFilter)
  // are the indirect path back into the input controllers. Guarded on focus
  // so a user mid-edit isn't clobbered, and on equality so an unrelated tab
  // notification (e.g. a row-edit) doesn't dirty the editors.
  void _onTabChanged() => _syncFromTab();

  void _syncFromTab() {
    final tab = widget.tab;
    if (!_selectFocus.hasFocus && _select.text != tab.selectList) {
      _select.text = tab.selectList;
    }
    if (!_filterFocus.hasFocus && _filter.text != tab.filter) {
      _filter.text = tab.filter;
    }
    if (!_orderFocus.hasFocus && _order.text != tab.orderBy) {
      _order.text = tab.orderBy;
    }
  }

  void _applySelect() => appState.tabsController.setTableSelect(
        widget.tab,
        _select.text.trim(),
      );

  void _applyFilter() => appState.tabsController.setTableFilter(
        widget.tab,
        _filter.text.trim(),
      );

  void _applyOrder() => appState.tabsController.setTableOrder(
        widget.tab,
        _order.text.trim(),
      );

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;

    final selectActive =
        tab.selectList.trim().isNotEmpty && tab.selectList.trim() != '*';
    final whereActive = tab.filter.trim().isNotEmpty;
    final orderActive = tab.orderBy.trim().isNotEmpty;

    final columns = appState.catalog.columnsFor(tab.table) ?? const [];
    CodeSuggestProvider clauseSuggest(List<String> keywords) {
      return (req) =>
          completeClause(req: req, columns: columns, extraKeywords: keywords);
    }

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
      selectSuggest: clauseSuggest(selectModifierKeywords),
      filterSuggest: clauseSuggest(whereOperatorKeywords),
      orderSuggest: clauseSuggest(orderModifierKeywords),
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
    required this.selectSuggest,
    required this.filterSuggest,
    required this.orderSuggest,
  });

  final CodeEditorController selectController;
  final CodeEditorController filterController;
  final CodeEditorController orderController;
  final FocusNode selectFocus;
  final FocusNode filterFocus;
  final FocusNode orderFocus;
  final VoidCallback onApplySelect;
  final VoidCallback onApplyFilter;
  final VoidCallback onApplyOrder;
  final bool selectActive;
  final bool whereActive;
  final bool orderActive;
  final CodeSuggestProvider selectSuggest;
  final CodeSuggestProvider filterSuggest;
  final CodeSuggestProvider orderSuggest;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        height: 78,
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
              suggest: filterSuggest,
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
              suggest: selectSuggest,
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
              suggest: orderSuggest,
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
    required this.suggest,
  });

  final String label;
  final CodeEditorController controller;
  final FocusNode focusNode;
  final VoidCallback onApply;
  final String hint;
  final bool active;
  final IconData actionIcon;
  final String actionTooltip;

  /// Omits the bottom hairline on the last row (the outer bar border covers it).
  final bool isLast;
  final CodeSuggestProvider suggest;

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
            child: Align(
              alignment: Alignment.centerLeft,
              child: CodeEditor(
                controller: widget.controller,
                focusNode: widget.focusNode,
                singleLine: true,
                fontSize: 11.5,
                cursorHeight: 12,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                background: Colors.transparent,
                hintText: widget.hint,
                hintStyle: AppTheme.mono(
                  size: 11.5,
                  color: AppColors.text4,
                ),
                onSubmit: widget.onApply,
                suggest: widget.suggest,
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
                      : AppColors.surfaceHover.withValues(alpha: 0),
                  border: Border(left: BorderSide(color: AppColors.hairline)),
                ),
                child: Icon(
                  widget.actionIcon,
                  size: 13,
                  color: widget.active ? AppColors.accent : AppColors.textMuted,
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
  const _PaginationBar({required this.tab});

  final TableTab tab;

  @override
  Widget build(BuildContext context) {
    final tabs = appState.tabsController;
    final canPrev = tab.page > 0 && !tab.loading;
    final canNext = tab.page < tab.pageCount - 1 && !tab.loading;
    final result = tab.result;
    final rowCount = result?.rows.length ?? 0;
    final pageCount = tab.pageCount;
    final pendingCount = tab.pendingOpCount;
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
              style: AppTheme.mono(size: 10.5, color: AppColors.textMuted),
            ),
          ],
          if (refreshedAt != null) ...[
            const PbDot(),
            PbStat(head: 'refreshed ', mid: formatPagebarClock(refreshedAt)),
          ],
          const Spacer(),
          if (pendingCount > 0) ...[
            _PendingActions(tab: tab, count: pendingCount),
            const PbDot(),
          ],
          RefreshDropdown(
            interval: tab.autoRefreshInterval,
            busy: tab.loading,
            canRefresh: !tab.loading,
            onManualRefresh: () => tabs.refreshTable(tab),
            onSetInterval: (d) => tabs.setTableAutoRefresh(tab, d),
          ),
          const PbDot(),
          PbChev(
            icon: Icons.chevron_left,
            tooltip: 'Previous page',
            onPressed: canPrev
                ? () => tabs.loadTablePage(tab, tab.page - 1)
                : null,
          ),
          PbChev(
            icon: Icons.chevron_right,
            tooltip: 'Next page',
            onPressed: canNext
                ? () => tabs.loadTablePage(tab, tab.page + 1)
                : null,
          ),
        ],
      ),
    );
  }
}

/// One bordered cluster surfacing the cross-tab pending edit count along
/// with direct Apply and Revert affordances. The count text opens the
/// statement-preview modal; the two icons act without confirmation.
class _PendingActions extends StatelessWidget {
  const _PendingActions({required this.tab, required this.count});

  final TableTab tab;
  final int count;

  @override
  Widget build(BuildContext context) {
    final busy = tab.applying;
    return Container(
      height: 22,
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: Radii.brSm,
        border: Border.all(color: AppColors.accentSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Hoverable(
            cursor: SystemMouseCursors.click,
            onTap: () => showPendingForTab(context, tab),
            builder: (context, hovering) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hovering
                    ? AppColors.accent.withValues(alpha: 0.18)
                    : Colors.transparent,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  bottomLeft: Radius.circular(4),
                ),
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
          ),
          Container(
            width: 1,
            height: 22,
            color: AppColors.accent.withValues(alpha: 0.25),
          ),
          _PendingIcon(
            icon: busy ? null : Icons.arrow_upward,
            tooltip: 'Apply pending edits',
            busy: busy,
            onTap: busy
                ? null
                : () => applyEditsForTab(context, tab),
          ),
          Container(
            width: 1,
            height: 22,
            color: AppColors.accent.withValues(alpha: 0.25),
          ),
          _PendingIcon(
            icon: Icons.close,
            tooltip: 'Discard pending edits',
            trailing: true,
            onTap: busy
                ? null
                : () => appState.tabsController.resetTableEdits(tab),
          ),
        ],
      ),
    );
  }
}

class _PendingIcon extends StatelessWidget {
  const _PendingIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.busy = false,
    this.trailing = false,
  });

  final IconData? icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool busy;
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Hoverable(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onTap: onTap,
        builder: (context, hovering) => Container(
          width: 24,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovering && enabled
                ? AppColors.accent.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: trailing
                ? const BorderRadius.only(
                    topRight: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                  )
                : BorderRadius.zero,
          ),
          child: busy
              ? SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.4,
                    color: AppColors.accent,
                  ),
                )
              : Icon(
                  icon,
                  size: 12,
                  color: enabled
                      ? AppColors.accent
                      : AppColors.accent.withValues(alpha: 0.4),
                ),
        ),
      ),
    );
  }
}
