import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_globals.dart';
import '../../theme/app_theme.dart';
import '../../theme/hugeicons.dart';
import '../widgets/context_menu.dart';
import 'highlighted_text.dart';
import 'table_detail.dart';
import 'tree_row.dart';

/// A collapsible kind folder inside a schema — "tables", "functions", … .
///
/// [WorkspaceUi] remembers toggled node ids, so a group open by default
/// stores its id when the user *closes* it: expanded is the default XOR the
/// toggle.
class SchemaObjectGroup extends StatelessWidget {
  const SchemaObjectGroup({
    super.key,
    required this.id,
    required this.label,
    required this.count,
    required this.indent,
    required this.forceExpanded,
    required this.children,
    this.expandedByDefault = false,
  });

  final String id;
  final String label;
  final int count;
  final int indent;

  /// Set while the sidebar search is active, so every match is visible.
  final bool forceExpanded;
  final bool expandedByDefault;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final expanded =
        forceExpanded || (expandedByDefault != appState.ui.isNodeExpanded(id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TreeRow(
          indent: indent,
          height: 24,
          onTap: () => appState.ui.toggleNode(id),
          children: [
            DetailChevron(expanded: expanded),
            Icon(
              expanded ? Hgi.folderOpen : Hgi.folder01,
              size: 13,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.ui(
                  size: 12,
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
        if (expanded) ...children,
      ],
    );
  }
}

/// A non-relation schema object: function, procedure, sequence or type.
/// Clicking opens its `CREATE` statement in the object tab.
class SchemaObjectRow extends StatelessWidget {
  const SchemaObjectRow({
    super.key,
    required this.indent,
    required this.icon,
    required this.iconColor,
    required this.name,
    required this.qualifiedName,
    required this.query,
    required this.onOpen,
    this.detail,
  });

  final int indent;
  final IconData icon;
  final Color iconColor;
  final String name;

  /// SQL-quoted `schema.name`, offered by the copy menu.
  final String qualifiedName;
  final String query;

  /// Trailing faint text: a signature, return type or base type.
  final String? detail;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return TreeRow(
      indent: indent,
      height: 24,
      onTap: onOpen,
      onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
      children: [
        // Aligns the icon with table rows, whose chevron occupies this slot.
        const SizedBox(width: 18),
        SizedBox(
          width: 14,
          height: 14,
          child: Center(child: Icon(icon, size: 12, color: iconColor)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SidebarHighlightedText(
            text: name,
            match: query,
            style: AppTheme.ui(
              size: 12,
              color: AppColors.textSecondary,
              weight: FontWeight.w400,
              letterSpacing: 0,
            ),
            trailing: detail == null
                ? null
                : TextSpan(
                    text: '  $detail',
                    style: AppTheme.mono(
                      size: 9.5,
                      color: AppColors.textMuted,
                      weight: FontWeight.w400,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  void _menu(BuildContext context, Offset position) {
    void copy(String value) => Clipboard.setData(ClipboardData(text: value));
    showContextMenu(
      context,
      globalPosition: position,
      entries: [
        CmItem(icon: Hgi.braces, label: 'Show DDL', onTap: onOpen),
        const CmDivider(),
        CmItem(icon: Hgi.tag01, label: 'Copy name', onTap: () => copy(name)),
        CmItem(
          icon: Hgi.hash,
          label: 'Copy qualified name',
          onTap: () => copy(qualifiedName),
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
}
