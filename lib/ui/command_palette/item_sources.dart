import 'package:flutter/material.dart';

import '../../models/db_object.dart';
import '../../state/app_globals.dart';
import '../../state/session_controller.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../../theme/hugeicons.dart';
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
      out.add(
        PaletteItem(
          kind: PaletteKind.command,
          title: 'New query',
          subtitle: 'Open a blank SQL editor tab',
          icon: Hgi.terminal,
          tokens: 'sql editor scratch run',
          run: tabs.newQueryTab,
        ),
      );
      final active = tabs.activeTab;
      if (active is TableTab) {
        out.add(
          PaletteItem(
            kind: PaletteKind.command,
            title: 'Refresh this table',
            subtitle: 'Re-fetch the current page of ${active.table.name}',
            icon: Hgi.refresh,
            tokens: 'reload requery',
            run: () => tabs.refreshTable(active),
          ),
        );
      }
      out.add(
        PaletteItem(
          kind: PaletteKind.command,
          title: 'Refresh catalog',
          subtitle: 'Re-introspect schemas, tables and types',
          icon: Hgi.refresh,
          tokens: 'reload schema introspect',
          run: appState.refreshCatalog,
        ),
      );
      if (history.canGoBack) {
        out.add(
          PaletteItem(
            kind: PaletteKind.command,
            title: 'Go back',
            subtitle: 'Step back through tab and filter history  ⌘[',
            icon: Hgi.arrowLeft01,
            tokens: 'history previous navigate',
            run: appState.historyBack,
          ),
        );
      }
      if (history.canGoForward) {
        out.add(
          PaletteItem(
            kind: PaletteKind.command,
            title: 'Go forward',
            subtitle: 'Step forward through history  ⌘]',
            icon: Hgi.arrowRight01,
            tokens: 'history next navigate',
            run: appState.historyForward,
          ),
        );
      }
    }

    out.add(
      PaletteItem(
        kind: PaletteKind.command,
        title: 'Toggle sidebar',
        subtitle: 'Show or hide the schema browser',
        icon: Hgi.sidebarLeft,
        tokens: 'panel tree tables hide',
        run: store.toggleSidebar,
      ),
    );
    out.add(
      PaletteItem(
        kind: PaletteKind.command,
        title: 'Activity log',
        subtitle: 'Show or hide the SQL event log  ⌘L',
        icon: Hgi.invoice01,
        tokens: 'events console history queries',
        run: eventLog.toggleVisible,
      ),
    );
    for (final (mode, title, subtitle, icon) in const [
      (
        AppThemeMode.dark,
        'Dark theme',
        'Pin the workspace to Aperture dark',
        Hgi.moon02,
      ),
      (
        AppThemeMode.light,
        'Light theme',
        'Pin the workspace to Aperture light',
        Hgi.sun03,
      ),
      (
        AppThemeMode.auto,
        'Auto theme',
        'Follow the macOS appearance',
        Hgi.contrast,
      ),
    ]) {
      out.add(
        PaletteItem(
          kind: PaletteKind.command,
          title: title,
          subtitle: subtitle,
          icon: icon,
          accent: store.themeMode == mode,
          tokens: 'appearance theme dark light auto system mode color',
          run: () => store.setThemeMode(mode),
        ),
      );
    }

    if (connected) {
      out.add(
        PaletteItem(
          kind: PaletteKind.command,
          title: 'Disconnect',
          subtitle: session.activeConnection?.summary ?? 'Close the session',
          icon: Hgi.power,
          tokens: 'close session logout end',
          run: appState.disconnect,
        ),
      );
    }
    out.add(
      PaletteItem(
        kind: PaletteKind.command,
        title: 'About Aperture',
        subtitle: 'Version, keyboard shortcuts and credits',
        icon: Hgi.informationCircle,
        tokens: 'help shortcuts version',
        run: () => showAboutAperture(context),
      ),
    );
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
        QueryTab() => ('SQL query', Hgi.terminal),
        TableTab() => ('Table view', Hgi.gridTable),
        SchemaTab() => ('Schema', Hgi.structure01),
      };
      out.add(
        PaletteItem(
          kind: PaletteKind.openTab,
          title: tab.title,
          subtitle: isActive ? '$label · in view now' : label,
          icon: icon,
          accent: isActive,
          run: () => tabs.selectTab(i),
        ),
      );
    }
    return out;
  }

  List<PaletteItem> savedQueries() {
    final tabs = appState.tabsController;
    final saved = appState.session.activeConnection?.savedQueries ?? const [];
    return [
      for (final q in saved)
        PaletteItem(
          kind: PaletteKind.savedQuery,
          title: q.name,
          subtitle: sqlPreview(q.sql),
          icon: Hgi.bookmark01,
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
          icon: Hgi.network,
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
      icon: t.isView ? Hgi.view : Hgi.table02,
      tokens: '${t.schema} ${t.qualifiedName}',
      run: () => appState.tabsController.openTable(t),
    );
  }

  List<PaletteItem> allTables() {
    final out = <PaletteItem>[];
    for (final s in appState.catalog.schemas) {
      for (final t in s.tables) {
        out.add(
          tableItem(
            t,
            PaletteKind.table,
            t.isView ? '${t.schema} · view' : t.schema,
          ),
        );
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
