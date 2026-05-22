import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/count_format.dart';
import '../../models/db_object.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/context_menu.dart';
import '../widgets/table_glyph.dart';
import 'highlighted_text.dart';
import 'sidebar_deps.dart';
import 'table_detail.dart';
import 'tree_row.dart';

class SchemaTableRow extends StatelessWidget {
  const SchemaTableRow({
    super.key,
    required this.table,
    required this.deps,
    required this.active,
    required this.isFav,
    required this.indent,
    required this.query,
    required this.scope,
  });

  final DbTable table;
  final SidebarDeps deps;
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
    final tint = AppColors.connectionTint(deps.session.activeConnection?.color);
    final nodeId = '$scope/${table.qualifiedKey}';
    final expanded = deps.ui.isNodeExpanded(nodeId);
    final row = _buildRow(context, tint, expanded, nodeId);
    if (!expanded) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        TableDetail(
          table: table,
          deps: deps,
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
      onTap: () => deps.tabs.openTable(table),
      onSecondaryTapDown: (d) =>
          openTableMenu(context, deps, table, d.globalPosition),
      childrenBuilder: (hovering) {
        final showStar = hovering || isFav;
        return [
          DetailChevron(
            expanded: expanded,
            onTap: () => deps.ui.toggleNode(nodeId),
          ),
          SizedBox(
            width: 14,
            height: 14,
            child: Center(child: _kindIcon(table.kind, active, tint)),
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
          if (showStar)
            StarToggle(
              filled: isFav,
              onTap: () => deps.perConnection.toggleFavorite(table),
            ),
        ];
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

class StarToggle extends StatelessWidget {
  const StarToggle({super.key, required this.filled, required this.onTap});

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

void openTableMenu(
  BuildContext context,
  SidebarDeps deps,
  DbTable table,
  Offset position,
) {
  final qualified = '"${table.schema}"."${table.name}"';
  final isFav = deps.perConnection.isFavorite(table);

  void copy(String value) => Clipboard.setData(ClipboardData(text: value));

  showContextMenu(
    context,
    globalPosition: position,
    entries: [
      CmItem(
        icon: Icons.north_east,
        label: 'Open data',
        onTap: () => deps.tabs.openTable(table),
      ),
      CmItem(
        icon: Icons.data_object,
        label: 'Show schema (CREATE TABLE)',
        onTap: () => deps.tabs.openSchema(table),
      ),
      const CmDivider(),
      CmItem(
        icon: isFav ? Icons.star : Icons.star_outline,
        label: isFav ? 'Remove from favourites' : 'Add to favourites',
        onTap: () => deps.perConnection.toggleFavorite(table),
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
        onTap: deps.appState.refreshCatalog,
      ),
    ],
  );
}
