import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/connection_config.dart';
import '../models/db_object.dart';
import '../models/value_format.dart';
import 'catalog_controller.dart';
import 'connection_registry.dart';
import 'event_log.dart';
import 'master_passphrase.dart';
import 'navigation_history.dart';
import 'per_connection_store.dart';
import 'preferences_controller.dart';
import 'session_controller.dart';
import 'tabs_controller.dart';
import 'workspace_tab.dart';
import 'workspace_ui.dart';

export 'session_controller.dart' show ConnectionStatus;

/// Callback the UI installs to handle the case where a connect attempt
/// needs the master passphrase but the session is locked. Should open
/// the unlock modal, await the user's response, and resolve to true on
/// successful unlock.
typedef PassphraseUnlockRequest = Future<bool> Function();

/// Coordinator over the focused controllers that make up the app's state.
///
/// Each concern (preferences, connection registry, live session, catalog,
/// per-connection bags, tabs, navigation history, schema-tree UI) lives in
/// its own [ChangeNotifier]. [AppState] owns one instance of each and wires
/// the cross-controller flows that span more than one of them (e.g.
/// connect → bump catalog generation → reset tabs → clear navigation
/// history).
///
/// The controllers are republished individually into the widget tree (see
/// `main.dart`'s [MultiProvider]); UI watches the specific controller it
/// depends on so an unrelated notification — a catalog tick, a cell edit,
/// a log append — never rebuilds it. [AppState] itself is read
/// non-reactively (via `context.read`) only to invoke the orchestration
/// methods below; it deliberately does NOT re-broadcast its children, so
/// nothing should `watch`/`select` it.
class AppState extends ChangeNotifier {
  AppState() {
    unawaited(_hydrate());
  }

  final PreferencesController preferences = PreferencesController();
  final MasterPassphrase masterPassphrase = MasterPassphrase();
  late final ConnectionRegistry registry = ConnectionRegistry(
    masterPassphrase: masterPassphrase,
  );
  final EventLog eventLog = EventLog();
  late final SessionController session = SessionController(log: eventLog);
  final CatalogController catalog = CatalogController();
  final NavigationHistory history = NavigationHistory();
  final WorkspaceUi ui = WorkspaceUi();

  /// Set by the UI at startup. AppState calls this when a connect
  /// attempt needs the master passphrase but the session is locked.
  PassphraseUnlockRequest? onPassphraseNeeded;

  late final PerConnectionStore perConnection = PerConnectionStore(
    session: session,
    registry: registry,
    catalog: catalog,
  );

  late final TabsController tabsController = TabsController(
    session: session,
    catalog: catalog,
    history: history,
    perConnection: perConnection,
  );

  Future<void> _hydrate() async {
    await preferences.hydrate();
    await masterPassphrase.hydrate();
    await registry.hydrate();
  }

  // --- Orchestration ---------------------------------------------------
  //
  // AppState's public surface is just the cross-controller flows below.
  // Per-controller getters / setters / methods live on the individual
  // controllers; widgets read those directly via the providers wired up
  // in main.dart.

  /// Update a saved connection in the registry. If the change targets the
  /// connection currently in session, the session's snapshot is refreshed
  /// in place so anything reading [SessionController.activeConnection]
  /// sees the new values without a reconnect.
  void updateConnection(ConnectionConfig config) {
    registry.update(config);
    if (session.activeConnection?.id == config.id) {
      session.setActiveConnection(config);
    }
  }

  Future<void> connect(ConnectionConfig config) async {
    tabsController.clear();
    history.clear();

    var resolved = config;
    final credential = await _resolveCredentialWithUnlock(resolved);
    switch (credential) {
      case CredentialError(message: final m):
        session.setError(m);
        return;
      case CredentialNeedsPassphrase():
        session.setError('Master passphrase required.');
        return;
      case CredentialOk(password: final p):
        if (p.isNotEmpty) resolved = resolved.copyWith(password: p);
    }

    final ok = await session.connect(resolved);
    if (!ok) return;

    final schemas = await _loadCatalog(awaitPhase1: false);
    if (schemas == null) return;

    final stamped = resolved.copyWith(lastConnectedAt: DateTime.now());
    // Empty password keeps the metadata-touch update from writing
    // plaintext back into the store.
    registry.update(stamped.copyWith(password: ''));
    session.setActiveConnection(stamped);
  }

  /// Resolves the password for [config], pumping the UI through the
  /// unlock modal if the credential source is encrypted and the master
  /// passphrase is locked. Re-tries the resolution exactly once after
  /// a successful unlock — further failures (wrong cipher, no callback)
  /// are surfaced as errors.
  Future<CredentialResult> _resolveCredentialWithUnlock(
    ConnectionConfig config,
  ) async {
    final first = await registry.readCredential(config);
    if (first is! CredentialNeedsPassphrase) return first;
    final ask = onPassphraseNeeded;
    if (ask == null) {
      return const CredentialError(
        'Master passphrase required but no UI is wired to prompt for it.',
      );
    }
    final unlocked = await ask();
    if (!unlocked) return first;
    return registry.readCredential(config);
  }

  Future<void> disconnect() async {
    await session.disconnect();
    catalog.reset();
    ui.reset();
    tabsController.clear();
    history.clear();
  }

  /// Reopen the dropped connection without disturbing the workspace.
  ///
  /// Reloads the catalog (OIDs can shift across server restarts) but
  /// keeps the open tabs and navigation history intact, so the user
  /// recovers to roughly where they were.
  Future<void> reconnect() async {
    final ok = await session.reconnect();
    if (!ok) return;
    await _loadCatalog(awaitPhase1: false);
  }

  Future<void> refreshCatalog() async {
    await _loadCatalog(awaitPhase1: true);
  }

  /// Shared catalog-loading shell for connect / reconnect / refresh.
  /// Bumps the generation, runs phase 0, auto-expands a lone schema, and
  /// then either awaits or backgrounds phase 1. Phase-0 and phase-1
  /// failures land on [CatalogController.lastError] for the sidebar to
  /// surface; this method never throws.
  Future<List<DbSchema>?> _loadCatalog({required bool awaitPhase1}) async {
    final svc = session.service;
    if (svc == null) return null;
    final schemas = await catalog.load(svc, awaitPhase1: awaitPhase1);
    if (schemas == null) return null;
    // Auto-expand on every catalog load (not just initial connect): a
    // reconnect or manual refresh that lands a one-schema database should
    // show its tables the same way the first connect did.
    if (schemas.length == 1) ui.expandSingleSchema(schemas.first.name);
    return schemas;
  }

  // --- Query messages --------------------------------------------------

  /// Wipe a query tab's message log: the in-memory copy on the tab plus
  /// the persisted copy on the active connection.
  void clearQueryMessages(QueryTab tab) {
    tab.messages.clear();
    perConnection.clearQueryMessages(tab.id);
    tab.markChanged();
  }

  // --- Navigation history ---------------------------------------------

  /// Walk one step back through the navigation history, applying the
  /// recorded tab/filter/sort snapshot. Implemented here rather than on
  /// [NavigationHistory] because the apply step has to coordinate with
  /// [TabsController].
  void historyBack() => history.back(_applySnapshot);

  /// Walk one step forward through the navigation history. See
  /// [historyBack].
  void historyForward() => history.forward(_applySnapshot);

  bool _applySnapshot(NavSnapshot snap) {
    final list = tabsController.tabs;
    final i = list.indexWhere((t) => t.id == snap.tabId);
    if (i == -1) return false;
    tabsController.selectTab(i);
    final tab = list[i];
    if (tab is TableTab && snap.hasTableState) {
      final filterChanged = tab.filter != snap.filter;
      final selectChanged = tab.selectList != snap.selectList;
      final orderChanged = tab.orderBy != snap.orderBy;
      final pageChanged = snap.page != null && tab.page != snap.page;
      tab.filter = snap.filter!;
      tab.selectList = snap.selectList!;
      tab.orderBy = snap.orderBy!;
      if (filterChanged || selectChanged || orderChanged || pageChanged) {
        unawaited(tabsController.loadTablePage(tab, snap.page ?? 0));
      }
    }
    return true;
  }

  // --- Cross-controller helpers ---------------------------------------

  Future<void> findRowInTable(
    DbTable refTable,
    String refColumn,
    Object? value,
  ) async {
    final tab = await tabsController.openTable(refTable);
    await tabsController.setTableFilter(
      tab,
      equalityFragment(refColumn, value),
    );
  }

  Future<void> followForeignKey(DbForeignKey fk, Object? value) async {
    if (!fk.isSingleColumn) return;
    final ref =
        catalog.relation(fk.refTableOid) ??
        catalog.relationByName(fk.refSchema, fk.refTable);
    if (ref == null) return;
    final tab = await tabsController.openTable(ref);
    await tabsController.setTableFilter(
      tab,
      equalityFragment(fk.refColumn, value),
    );
  }

  /// Drain any pending debounced writes to `connections.json` so a quit
  /// while a favourite toggle / recent track / query autosave is still
  /// buffered doesn't lose the mutation. `dispose()` can't be async, so
  /// the app's shutdown hook (`AppLifecycleListener.onExitRequested`)
  /// awaits this before letting Cocoa terminate the process.
  Future<void> flush() => registry.flush();

  @override
  void dispose() {
    // AppState owns the controllers' lifecycle. The `.value` providers in
    // `main.dart` republish these same instances but never dispose them,
    // so disposal stays here and happens exactly once.
    tabsController.dispose();
    perConnection.dispose();
    history.dispose();
    catalog.dispose();
    session.dispose();
    registry.dispose();
    preferences.dispose();
    ui.dispose();
    eventLog.dispose();
    super.dispose();
  }
}
