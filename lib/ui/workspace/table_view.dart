import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/db_object.dart';
import '../../models/order_term.dart';
import '../../models/time_ago.dart';
import '../../models/value_format.dart';
import '../../state/app_state.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../edits/pending_edits_modal.dart';
import '../export/export_dialog.dart';
import '../widgets/common.dart';
import '../widgets/context_menu.dart';
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

  void _previewEdits() {
    final statements = widget.state.previewEditStatements(widget.tab);
    showPendingEditsModal(context, statements: statements);
  }

  void _openExport() {
    final tab = widget.tab;
    final result = tab.result;
    if (result == null) return;
    final timestamp = filenameTimestamp();
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── action strip ──
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.hairline)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: Insets.md),
          child: Row(
            children: [
              _TableIdentity(tab: tab),
              const Spacer(),
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
              _RefreshSplitButton(
                tab: tab,
                onRefresh: () => widget.state.refreshTable(tab),
                onPickInterval: (d) =>
                    widget.state.setTableAutoRefresh(tab, d),
              ),
              const SizedBox(width: 4),
              IconAction(
                icon: Icons.ios_share,
                tooltip: 'Export…',
                onPressed: tab.result == null ? null : _openExport,
              ),
            ],
          ),
        ),
        // ── clause bar ──
        _ClauseBar(
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
        ),
      ],
    );
  }
}

/// Split-button: left half re-runs the current query, right half opens an
/// auto-refresh interval picker. When an interval is active the shell paints
/// in the accent and the live interval renders next to the icon, so the user
/// always knows the table is updating itself.
class _RefreshSplitButton extends StatefulWidget {
  const _RefreshSplitButton({
    required this.tab,
    required this.onRefresh,
    required this.onPickInterval,
  });

  final TableTab tab;
  final VoidCallback onRefresh;
  final void Function(Duration?) onPickInterval;

  @override
  State<_RefreshSplitButton> createState() => _RefreshSplitButtonState();
}

class _RefreshSplitButtonState extends State<_RefreshSplitButton> {
  static const List<(Duration, String)> _intervals = [
    (Duration(seconds: 5), '5s'),
    (Duration(seconds: 15), '15s'),
    (Duration(seconds: 30), '30s'),
    (Duration(minutes: 1), '1m'),
    (Duration(minutes: 5), '5m'),
  ];

  final GlobalKey _anchorKey = GlobalKey();

  void _openMenu() {
    final ctx = _anchorKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset(0, box.size.height + 4));
    final current = widget.tab.autoRefreshInterval;

    showContextMenu(
      context,
      globalPosition: origin,
      entries: [
        CmItem(
          icon: Icons.refresh,
          label: 'Refresh now',
          shortcut: '⌘R',
          onTap: widget.onRefresh,
        ),
        const CmDivider(),
        CmItem(
          icon: current == null ? Icons.check : null,
          label: 'Auto-refresh off',
          onTap: () => widget.onPickInterval(null),
        ),
        for (final (duration, label) in _intervals)
          CmItem(
            icon: current == duration ? Icons.check : null,
            label: 'Every $label',
            onTap: () => widget.onPickInterval(duration),
          ),
      ],
    );
  }

  String _intervalLabel(Duration d) {
    for (final (dur, label) in _intervals) {
      if (dur == d) return label;
    }
    return d.inSeconds < 60 ? '${d.inSeconds}s' : '${d.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final disabled = tab.loading;
    final active = tab.autoRefreshInterval != null;
    final shellBorder = active ? AppColors.accent : AppColors.border;

    return Container(
      key: _anchorKey,
      height: 28,
      decoration: BoxDecoration(
        color: active ? AppColors.accentSoft : Colors.transparent,
        borderRadius: Radii.brSm,
        border: Border.all(color: shellBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── refresh-now half ──
          Tooltip(
            message: active
                ? 'Refresh now · auto ${_intervalLabel(tab.autoRefreshInterval!)}'
                : 'Refresh',
            child: Hoverable(
              cursor: disabled
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.click,
              onTap: disabled ? null : widget.onRefresh,
              builder: (context, hovering) => AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: 26,
                padding: EdgeInsets.symmetric(
                  horizontal: active ? 9 : 7,
                ),
                decoration: BoxDecoration(
                  color: hovering && !disabled
                      ? (active
                          ? AppColors.accentSoft
                          : AppColors.surfaceHover)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(5),
                    bottomLeft: Radius.circular(5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _RefreshIcon(spinning: tab.loading, active: active),
                    if (active) ...[
                      const SizedBox(width: 7),
                      Text(
                        _intervalLabel(tab.autoRefreshInterval!),
                        style: AppTheme.mono(
                          size: 10.5,
                          color: AppColors.accent,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // ── hairline divider ──
          Container(width: 1, height: 26, color: shellBorder),
          // ── dropdown half ──
          Tooltip(
            message: 'Auto-refresh…',
            child: Hoverable(
              onTap: _openMenu,
              builder: (context, hovering) => AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 18,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hovering
                      ? (active
                          ? AppColors.accentSoft
                          : AppColors.surfaceHover)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(5),
                    bottomRight: Radius.circular(5),
                  ),
                ),
                child: Icon(
                  Icons.expand_more,
                  size: 13,
                  color: active
                      ? AppColors.accent
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Refresh glyph that rotates continuously while a fetch is in-flight, so
/// auto-refresh ticks are visible to the eye without a separate progress bar.
class _RefreshIcon extends StatefulWidget {
  const _RefreshIcon({required this.spinning, required this.active});
  final bool spinning;
  final bool active;

  @override
  State<_RefreshIcon> createState() => _RefreshIconState();
}

class _RefreshIconState extends State<_RefreshIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _RefreshIcon old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.spinning && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.active ? AppColors.accent : AppColors.textSecondary;
    return RotationTransition(
      turns: _ctrl,
      child: Icon(Icons.refresh, size: 14, color: color),
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


/// Stacked clause bar with three rows: WHERE, SELECT, ORDER.
/// Each row shares a narrow left decorative strip (accent gradient) with
/// the clause label column separated by a hairline, then the input, then
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
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
      constraints: const BoxConstraints(minHeight: 26),
      decoration: BoxDecoration(
        border: widget.isLast
            ? null
            : Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── label ──
          Container(
            width: 52,
            constraints: const BoxConstraints(minHeight: 26),
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
            padding: const EdgeInsets.only(left: 10, right: 8),
            child: Text(
              widget.label,
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
                    vertical: 6,
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
          // ── action icon ──
          Tooltip(
            message: widget.actionTooltip,
            child: Hoverable(
              cursor: SystemMouseCursors.click,
              onTap: widget.onApply,
              builder: (context, hovering) => AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: 28,
                height: 26,
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


/// Tight pill that signals the count of pending cell edits. Click to preview
/// the generated UPDATE statements.
class _EditCountBadge extends StatelessWidget {
  const _EditCountBadge({required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final clickable = onTap != null;
    final tooltip = clickable
        ? '$count pending edit${count == 1 ? '' : 's'} — click to preview'
        : '$count pending edit${count == 1 ? '' : 's'}';

    return Tooltip(
      message: tooltip,
      child: Hoverable(
        cursor:
            clickable ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onTap: onTap,
        builder: (context, hovering) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: hovering && clickable
                ? AppColors.accent.withValues(alpha: 0.32)
                : AppColors.accentSoft,
            borderRadius: Radii.brSm,
          ),
          child: Row(
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '$count',
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
      decoration: BoxDecoration(
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
