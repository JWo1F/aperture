import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/query_result.dart';
import '../../models/time_ago.dart';
import '../../state/app_globals.dart';
import '../../state/workspace_tab.dart';
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

void openExportForActiveTab(BuildContext context, WorkspaceTab? tab) {
  final timestamp = filenameTimestamp();
  if (tab is TableTab) {
    final result = tab.result;
    if (result == null) return;
    showExportDialog(
      context,
      target: ExportTarget(
        suggestedFilename: '${tab.table.name}_$timestamp.csv',
        currentResult: result,
        fetchAll: () => appState.tabsController.fetchAllForExport(tab),
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

Future<void> applyEditsForTab(TableTab tab) async {
  await appState.tabsController.applyTableEdits(tab);
}

void showPendingForTab(BuildContext context, TableTab tab) {
  final tabs = appState.tabsController;
  final statements = tabs.previewEditStatements(tab);
  showPendingEditsModal(
    context,
    statements: statements,
    onApply: () => applyEditsForTab(tab),
    onRevert: () => tabs.resetTableEdits(tab),
  );
}
