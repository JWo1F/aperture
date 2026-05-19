import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/order_term.dart';
import '../../models/value_format.dart';
import '../../state/app_state.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
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
  late final SqlHighlightController _filter;
  late final SqlHighlightController _order;
  final FocusNode _orderFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _filter = SqlHighlightController(text: widget.tab.filter);
    _order = SqlHighlightController(text: widget.tab.orderBy);
  }

  @override
  void dispose() {
    _filter.dispose();
    _order.dispose();
    _orderFocus.dispose();
    super.dispose();
  }

  void _applyFilter() =>
      widget.state.setTableFilter(widget.tab, _filter.text.trim());

  void _applyOrder() =>
      widget.state.setTableOrder(widget.tab, _order.text.trim());

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

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: Insets.md),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Icon(
            tab.table.isView
                ? Icons.visibility_outlined
                : Icons.table_rows_outlined,
            size: 14,
            color: AppColors.accent,
          ),
          const SizedBox(width: 6),
          Text(
            '${tab.table.schema}.${tab.table.name}',
            style: AppTheme.mono(size: 12.5, weight: FontWeight.w600),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            flex: 3,
            child: _QueryField(
              prefix: 'WHERE',
              controller: _filter,
              onApply: _applyFilter,
              hint: 'filter rows — e.g. status = \'active\'',
            ),
          ),
          const SizedBox(width: Insets.sm),
          Expanded(
            flex: 2,
            child: _QueryField(
              prefix: 'ORDER BY',
              controller: _order,
              focusNode: _orderFocus,
              onApply: _applyOrder,
              hint: 'click a column header',
            ),
          ),
          if (!tab.table.isView) ...[
            const SizedBox(width: Insets.md),
            _EditCountBadge(count: tab.edits.length),
            const SizedBox(width: Insets.sm),
            AppButton(
              label: 'Reset',
              icon: Icons.undo,
              onPressed: tab.hasEdits && !tab.applying
                  ? () => widget.state.resetTableEdits(tab)
                  : null,
            ),
            const SizedBox(width: Insets.sm),
            AppButton(
              label: tab.applying ? 'Applying…' : 'Apply',
              icon: Icons.check,
              primary: true,
              onPressed:
                  tab.hasEdits && !tab.applying ? _applyEdits : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// A boxed query-fragment input with a coloured prefix label, applied on ↵.
class _QueryField extends StatelessWidget {
  const _QueryField({
    required this.prefix,
    required this.controller,
    required this.onApply,
    required this.hint,
    this.focusNode,
  });

  final String prefix;
  final TextEditingController controller;
  final VoidCallback onApply;
  final String hint;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Text(
              prefix,
              style: AppTheme.mono(
                size: 10.5,
                color: AppColors.accent,
                weight: FontWeight.w600,
              ),
            ),
          ),
          Container(width: 1, height: 30, color: AppColors.border),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): onApply,
              },
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                cursorColor: AppColors.accent,
                style: AppTheme.mono(size: 11.5),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 9,
                  ),
                  hintText: hint,
                  hintStyle:
                      AppTheme.mono(size: 11.5, color: AppColors.textMuted),
                ),
              ),
            ),
          ),
          IconAction(
            icon: Icons.play_arrow,
            tooltip: 'Apply ($prefix) — ↵',
            onPressed: onApply,
          ),
          const SizedBox(width: 2),
        ],
      ),
    );
  }
}

class _EditCountBadge extends StatelessWidget {
  const _EditCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.accent),
      ),
      child: Text(
        '$count pending',
        style: AppTheme.mono(size: 10.5, color: AppColors.accent),
      ),
    );
  }
}

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
      height: 36,
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
          const SizedBox(width: Insets.sm),
          Text(
            'Page ${tab.page + 1} of ${tab.pageCount}',
            style: AppTheme.mono(size: 11, color: AppColors.textSecondary),
          ),
          const Spacer(),
          Text(
            '$first–$last of ${tab.totalRows} rows',
            style: AppTheme.mono(size: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
