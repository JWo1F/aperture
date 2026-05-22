import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/saved_query.dart';
import '../../models/time_ago.dart';
import '../../theme/app_theme.dart';
import '../widgets/context_menu.dart';
import '../widgets/text_prompt_dialog.dart';
import 'highlighted_text.dart';
import 'sidebar_deps.dart';
import 'tree_row.dart';

class SavedQueryRow extends StatefulWidget {
  const SavedQueryRow({
    super.key,
    required this.query,
    required this.active,
    required this.deps,
    required this.match,
  });

  final SavedQuery query;
  final bool active;
  final SidebarDeps deps;
  final String match;

  @override
  State<SavedQueryRow> createState() => _SavedQueryRowState();
}

class _SavedQueryRowState extends State<SavedQueryRow> {
  void _openMenu(Offset position) {
    final query = widget.query;
    final tabs = widget.deps.tabs;
    void copy(String text) => Clipboard.setData(ClipboardData(text: text));

    showContextMenu(
      context,
      globalPosition: position,
      entries: [
        CmItem(
          icon: Icons.north_east,
          label: 'Open',
          onTap: () => tabs.openSavedQuery(query),
        ),
        CmItem(
          icon: Icons.edit_outlined,
          label: 'Rename…',
          onTap: _renameDialog,
        ),
        CmItem(
          icon: Icons.content_copy,
          label: 'Duplicate',
          onTap: () => tabs.duplicateSavedQuery(query.id),
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
          onTap: () => tabs.deleteSavedQuery(query.id),
        ),
      ],
    );
  }

  Future<void> _renameDialog() async {
    final next = await showTextPrompt(
      context,
      title: 'Rename query',
      initial: widget.query.name,
      actionLabel: 'Rename',
    );
    if (next != null && next.trim().isNotEmpty) {
      widget.deps.tabs.renameQuery(widget.query.id, next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ts = widget.query.updatedAt;
    final tint = AppColors.connectionTint(
      widget.deps.session.activeConnection?.color,
    );
    return TreeRow(
      indent: 0,
      height: 24,
      active: widget.active,
      tint: tint,
      padding: const EdgeInsets.only(left: 14, right: 6),
      onTap: () => widget.deps.tabs.openSavedQuery(widget.query),
      onSecondaryTapDown: (d) => _openMenu(d.globalPosition),
      children: [
        Icon(
          Icons.code_rounded,
          size: 12,
          color: widget.active ? tint : AppColors.textMuted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SidebarHighlightedText(
            text: widget.query.name,
            match: widget.match,
            style: AppTheme.ui(
              size: 12,
              color: widget.active
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
              weight: widget.active ? FontWeight.w600 : FontWeight.w400,
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
    );
  }
}
