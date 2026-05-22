import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/query_result.dart';
import '../../models/time_ago.dart';
import '../../state/tabs_controller.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../edits/pending_edits_modal.dart';
import '../export/export_dialog.dart';

/// Reveals the app's Application Support directory — home of
/// connections.json and the rest of the persisted config — in Finder. The
/// app is unsandboxed, so a plain `open` needs no security-scoped bookmark.
Future<void> revealConfigFolder() async {
  final dir = await getApplicationSupportDirectory();
  await Process.run('open', [dir.path]);
}

/// Returns the [QueryResult] the toolbar's Export action would feed to the
/// dialog, or null if [tab] has nothing exportable. Table and query tabs
/// both qualify; lifecycle tabs (schema) never do.
QueryResult? exportableResult(WorkspaceTab? tab) {
  if (tab is TableTab) return tab.result;
  if (tab is QueryTab) return tab.result;
  return null;
}

void openExportForActiveTab(
  BuildContext context,
  TabsController tabs,
  WorkspaceTab? tab,
) {
  final timestamp = filenameTimestamp();
  if (tab is TableTab) {
    final result = tab.result;
    if (result == null) return;
    showExportDialog(
      context,
      target: ExportTarget(
        suggestedFilename: '${tab.table.name}_$timestamp.csv',
        currentResult: result,
        fetchAll: () => tabs.fetchAllForExport(tab),
        totalRowsForAll: tab.totalRows,
      ),
    );
    return;
  }
  if (tab is QueryTab) {
    final result = tab.result;
    if (result == null) return;
    showExportDialog(
      context,
      target: ExportTarget(
        suggestedFilename: 'query_$timestamp.csv',
        currentResult: result,
      ),
    );
  }
}

void openPendingForActiveTab(BuildContext context, TabsController tabs) {
  final tab = tabs.activeTab;
  if (tab is TableTab && tab.hasEdits) {
    _showPending(context, tabs, tab);
    return;
  }
  // Active tab has no edits; surface the first tab that does.
  for (final t in tabs.tabs) {
    if (t is TableTab && t.hasEdits) {
      tabs.selectTab(tabs.tabs.indexOf(t));
      _showPending(context, tabs, t);
      return;
    }
  }
}

void _showPending(BuildContext context, TabsController tabs, TableTab tab) {
  final statements = tabs.previewEditStatements(tab);
  final messenger = ScaffoldMessenger.maybeOf(context);
  showPendingEditsModal(
    context,
    statements: statements,
    onApply: () async {
      final error = await tabs.applyTableEdits(tab);
      if (error != null && messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: AppColors.surfaceAlt,
            content: Text(
              'Apply failed: $error',
              style: AppTheme.mono(size: 11.5, color: AppColors.error),
            ),
          ),
        );
      }
    },
    onRevert: () => tabs.resetTableEdits(tab),
  );
}
