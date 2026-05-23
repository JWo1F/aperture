import 'package:flutter/material.dart';

import '../../models/db_object.dart';
import '../../state/app_globals.dart';
import '../../state/session_controller.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../about/about_dialog.dart';
import 'item_model.dart';

/// Builds the palette's pool of searchable items from the live controllers.
/// The palette's [BuildContext] is needed by a single command (About) which
/// opens a modal anchored on the live overlay.
class PaletteItemSource {
  PaletteItemSource({required this.context});

  final BuildContext context;

  List<PaletteItem> commands() {
    final session = appState.session;
    final tabs = appState.tabsController;
    final history = appState.history;
    final store = appState.store;
    final eventLog = appState.eventLog;
    final connected = session.status == ConnectionStatus.connected;
    final out = <PaletteItem>[];

    if (connected) {
      out.add(PaletteItem(
        kind: PaletteKind.command,
        title: 'New query',
        subtitle: 'Open a blank SQL editor tab',
        icon: Icons.terminal_rounded,
        tokens: 'sql editor scratch run',
        run: tabs.newQueryTab,
      ));
      final active = tabs.activeTab;
      if (active is TableTab) {
        out.add(PaletteItem(
          kind: PaletteKind.command,
          title: 'Refresh this table',
          subtitle: 'Re-fetch the current page of ${active.table.name}',
          icon: Icons.sync_rounded,
          tokens: 'reload requery',
          run: () => tabs.refreshTable(active),
        ));
      }
      out.add(PaletteItem(
        kind: PaletteKind.command,
        title: 'Refresh catalog',
        subtitle: 'Re-introspect schemas, tables and types',
        icon: Icons.refresh_rounded,
        tokens: 'reload schema introspect',
        run: appState.refreshCatalog,
      ));
      if (history.canGoBack) {
        out.add(PaletteItem(
          kind: PaletteKind.command,
          title: 'Go back',
          subtitle: 'Step back through tab and filter history  ⌘[',
          icon: Icons.arrow_back_rounded,
          tokens: 'history previous navigate',
          run: appState.historyBack,
        ));
      }
      if (history.canGoForward) {
        out.add(PaletteItem(
          kind: PaletteKind.command,
          title: 'Go forward',
          subtitle: 'Step forward through history  ⌘]',
          icon: Icons.arrow_forward_rounded,
          tokens: 'history next navigate',
          run: appState.historyForward,
        ));
      }
    }

    out.add(PaletteItem(
      kind: PaletteKind.command,
      title: 'Toggle sidebar',
      subtitle: 'Show or hide the schema browser',
      icon: Icons.view_sidebar_outlined,
      tokens: 'panel tree tables hide',
      run: store.toggleSidebar,
    ));
    out.add(PaletteItem(
      kind: PaletteKind.command,
      title: 'Activity log',
      subtitle: 'Show or hide the SQL event log  ⌘L',
      icon: Icons.receipt_long_outlined,
      tokens: 'events console history queries',
      run: eventLog.toggleVisible,
    ));
    final dark = store.brightness == AppBrightness.dark;
    out.add(PaletteItem(
      kind: PaletteKind.command,
      title: dark ? 'Switch to light theme' : 'Switch to dark theme',
      subtitle: 'Flip the workspace between Aperture dark and light',
      icon: dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
      tokens: 'appearance dark light mode color',
      run: store.toggleBrightness,
    ));

    if (connected) {
      out.add(PaletteItem(
        kind: PaletteKind.command,
        title: 'Disconnect',
        subtitle: session.activeConnection?.summary ?? 'Close the session',
        icon: Icons.power_settings_new_rounded,
        tokens: 'close session logout end',
        run: appState.disconnect,
      ));
    }
    out.add(PaletteItem(
      kind: PaletteKind.command,
      title: 'About Aperture',
      subtitle: 'Version, keyboard shortcuts and credits',
      icon: Icons.info_outline_rounded,
      tokens: 'help shortcuts version',
      run: () => showAboutAperture(context),
    ));
    return out;
  }

  List<PaletteItem> openTabs() {
    final tabs = appState.tabsController;
    final activeId = tabs.activeTab?.id;
    final out = <PaletteItem>[];
    for (var i = 0; i < tabs.tabs.length; i++) {
      final tab = tabs.tabs[i];
      final isActive = tab.id == activeId;
      final (label, icon) = switch (tab) {
        QueryTab() => ('SQL query', Icons.terminal_rounded),
        TableTab() => ('Table view', Icons.grid_on_rounded),
        SchemaTab() => ('Schema', Icons.schema_outlined),
      };
      out.add(PaletteItem(
        kind: PaletteKind.openTab,
        title: tab.title,
        subtitle: isActive ? '$label · in view now' : label,
        icon: icon,
        accent: isActive,
        run: () => tabs.selectTab(i),
      ));
    }
    return out;
  }

  List<PaletteItem> savedQueries() {
    final tabs = appState.tabsController;
    final saved =
        appState.session.activeConnection?.savedQueries ?? const [];
    return [
      for (final q in saved)
        PaletteItem(
          kind: PaletteKind.savedQuery,
          title: q.name,
          subtitle: sqlPreview(q.sql),
          icon: Icons.bookmark_outline_rounded,
          tokens: q.sql,
          run: () => tabs.openSavedQuery(q),
        ),
    ];
  }

  List<PaletteItem> connections() {
    final activeId = appState.session.activeConnection?.id;
    return [
      for (final c in appState.store.connections)
        PaletteItem(
          kind: PaletteKind.connection,
          title: c.name,
          subtitle: c.id == activeId ? '${c.summary} · connected' : c.summary,
          icon: c.id == activeId ? Icons.lan_rounded : Icons.lan_outlined,
          accent: c.id == activeId,
          tokens: '${c.host} ${c.database} ${c.username}',
          run: () => appState.connect(c),
        ),
    ];
  }

  PaletteItem tableItem(DbTable t, PaletteKind kind, String subtitle) {
    return PaletteItem(
      kind: kind,
      title: t.name,
      subtitle: subtitle,
      icon: t.isView ? Icons.visibility_outlined : Icons.table_rows_outlined,
      tokens: '${t.schema} ${t.qualifiedName}',
      run: () => appState.tabsController.openTable(t),
    );
  }

  List<PaletteItem> allTables() {
    final out = <PaletteItem>[];
    for (final s in appState.catalog.schemas) {
      for (final t in s.tables) {
        out.add(tableItem(
          t,
          PaletteKind.table,
          t.isView ? '${t.schema} · view' : t.schema,
        ));
      }
    }
    return out;
  }
}

String sqlPreview(String sql) {
  final flat = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.isEmpty) return 'Empty query';
  return flat.length > 96 ? '${flat.substring(0, 96)}…' : flat;
}
