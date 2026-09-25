import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/count_format.dart';
import '../../models/db_object.dart';
import '../../state/app_globals.dart';
import '../../state/connection_views.dart';
import '../../theme/app_theme.dart';
import '../../theme/hugeicons.dart';
import '../widgets/context_menu.dart';
import '../widgets/table_glyph.dart';
import 'highlighted_text.dart';
import 'table_detail.dart';
import 'tree_row.dart';

class SchemaTableRow extends StatelessWidget {
  const SchemaTableRow({
    super.key,
    required this.table,
    required this.active,
    required this.isFav,
    required this.indent,
    required this.query,
    required this.scope,
  });

  final DbTable table;
  final bool active;
  final bool isFav;
  final int indent;
  final String query;

  /// Section the row lives in (`pin` / `freq` / `tree`). Folded into the
  /// detail-tree node ids so the same table expanded in one section stays
  /// collapsed in the others.
  final String scope;

  @override
  Widget build(BuildContext context) {
    final tint =
        AppColors.connectionTint(appState.session.activeConnection?.color);
    final nodeId = '$scope/${table.qualifiedKey}';
    final expanded = appState.ui.isNodeExpanded(nodeId);
    final row = _buildRow(context, tint, expanded, nodeId);
    if (!expanded) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        TableDetail(
          table: table,
          indent: indent + 1,
          scope: scope,
        ),
      ],
    );
  }

  Widget _buildRow(
    BuildContext context,
    Color tint,
    bool expanded,
    String nodeId,
  ) {
    final stat = tableStat(table);
    return TreeRow(
      indent: indent,
      height: 24,
      active: active,
      tint: tint,
      onTap: () => appState.tabsController.openTable(table),
      onSecondaryTapDown: (d) =>
          openTableMenu(context, table, d.globalPosition),
      childrenBuilder: (_) {
        return [
          DetailChevron(
            expanded: expanded,
            onTap: () => appState.ui.toggleNode(nodeId),
          ),
          SizedBox(
            width: 14,
            height: 14,
            child: Center(child: _kindIcon(table, active, tint)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SidebarHighlightedText(
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
        ];
      },
    );
  }

  Widget _kindIcon(DbTable table, bool active, Color tint) {
    if (table.partitioned) {
      return Icon(
        Hgi.tableRowsSplit,
        size: 12,
        color: active ? tint : AppColors.textMuted,
      );
    }
    switch (table.kind) {
      case DbRelationKind.table:
        return TableGlyph(
          size: 12,
          color: active ? tint : AppColors.textMuted,
        );
      case DbRelationKind.view:
        return Icon(
          Hgi.view,
          size: 12,
          color: active ? tint : AppColors.info,
        );
      case DbRelationKind.materializedView:
        return Icon(
          Hgi.layers01,
          size: 12,
          color: active ? tint : AppColors.info,
        );
    }
  }
}

void openTableMenu(BuildContext context, DbTable table, Offset position) {
  final qualified = '"${table.schema}"."${table.name}"';
  final activeConn = appState.session.activeConnection;
  final isFav = isFavoriteTable(activeConn, table);

  void copy(String value) => Clipboard.setData(ClipboardData(text: value));

  showContextMenu(
    context,
    globalPosition: position,
    entries: [
      CmItem(
        icon: Hgi.arrowUpRight01,
        label: 'Open data',
        onTap: () => appState.tabsController.openTable(table),
      ),
      CmItem(
        icon: Hgi.braces,
        label: 'Show schema (CREATE TABLE)',
        onTap: () => appState.tabsController.openSchema(table),
      ),
      const CmDivider(),
      CmItem(
        icon: Hgi.star,
        label: isFav ? 'Remove from favourites' : 'Add to favourites',
        onTap: () {
          if (activeConn != null) {
            appState.store.toggleFavorite(activeConn.id, table);
          }
        },
      ),
      const CmDivider(),
      CmItem(
        icon: Hgi.tag01,
        label: 'Copy name',
        onTap: () => copy(table.name),
      ),
      CmItem(
        icon: Hgi.hash,
        label: 'Copy qualified name',
        onTap: () => copy(qualified),
      ),
      CmItem(
        icon: Hgi.sourceCode,
        label: 'Copy SELECT *',
        onTap: () => copy('SELECT * FROM $qualified;'),
      ),
      const CmDivider(),
      CmItem(
        icon: Hgi.refresh,
        label: 'Refresh catalog',
        onTap: appState.refreshCatalog,
      ),
    ],
  );
}
