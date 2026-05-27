import 'dart:async';

import '../models/connection_config.dart';
import '../models/db_object.dart';
import '../models/value_format.dart';
import 'app_store.dart';
import 'catalog_controller.dart';
import 'event_log.dart';
import 'navigation_history.dart';
import 'session_controller.dart';
import 'tabs_controller.dart';
import 'toast_controller.dart';
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
/// Persistence is concentrated in [AppStore]; the runtime-only controllers
/// (live database session, loaded catalog, tabs, navigation history,
/// schema-tree UI, in-memory event log) live alongside it. AppState's
/// public surface is the cross-controller orchestration below (connect,
/// disconnect, reconnect, refreshCatalog, navigation playback, FK follow).
///
/// Deliberately not a [ChangeNotifier]: AppState has no observable state
/// of its own — widgets only `read` it to invoke methods. Any reactive
/// data lives on the individual controllers, each provided separately.
class AppState {
  AppState({AppStore? store}) : store = store ?? AppStore() {
    this.store.addListener(_syncSessionFromStore);
  }

  final AppStore store;
  final EventLog eventLog = EventLog();
  late final SessionController session = SessionController(log: eventLog);
  final CatalogController catalog = CatalogController();
  final NavigationHistory history = NavigationHistory();
  final WorkspaceUi ui = WorkspaceUi();
  final ToastController toasts = ToastController();

  /// Set by the UI at startup. AppState calls this when a connect
  /// attempt needs the master passphrase but the session is locked.
  PassphraseUnlockRequest? onPassphraseNeeded;

  late final TabsController tabsController = TabsController(
    session: session,
    catalog: catalog,
    history: history,
    store: store,
    toasts: toasts,
  );

  void _syncSessionFromStore() {
    final id = session.activeConnection?.id;
    if (id == null) return;
    final fresh = store.connectionById(id);
    if (fresh == null) return;
    if (identical(fresh, session.activeConnection)) return;
    session.setActiveConnection(fresh);
  }

  /// Single async load on startup. Reads `store.json` into [store].
  Future<void> load() => store.load();

  // --- Orchestration ---------------------------------------------------

  /// Update a saved connection in the store. The store-listener above
  /// keeps the session's snapshot fresh when the change targets the
  /// active connection — callers don't need to touch session themselves.
  void updateConnection(ConnectionConfig config) {
    store.updateConnection(config);
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
        resolved = resolved.copyWith(runtimePassword: p);
    }

    final ok = await session.connect(resolved);
    if (!ok) return;

    final schemas = await _loadCatalog(awaitPhase1: false);
    if (schemas == null) return;

    store.touchLastConnected(resolved.id, DateTime.now());
    // _syncSessionFromStore already pushed the stamped config into the
    // session via the AppStore listener, so we just need the runtime
    // password overlaid back on top for use by the driver.
    final stored = store.connectionById(resolved.id);
    if (stored != null) {
      session.setActiveConnection(
        stored.copyWith(runtimePassword: resolved.runtimePassword),
      );
    }
  }

  /// Resolves the password for [config], pumping the UI through the
  /// unlock modal if the credential source is encrypted and the master
  /// passphrase is locked.
  Future<CredentialResult> _resolveCredentialWithUnlock(
    ConnectionConfig config,
  ) async {
    final first = await store.readCredential(config);
    if (first is! CredentialNeedsPassphrase) return first;
    final ask = onPassphraseNeeded;
    if (ask == null) {
      return const CredentialError(
        'Master passphrase required but no UI is wired to prompt for it.',
      );
    }
    final unlocked = await ask();
    if (!unlocked) return first;
    return store.readCredential(config);
  }

  Future<void> disconnect() async {
    await session.disconnect();
    catalog.reset();
    ui.reset();
    tabsController.clear();
    history.clear();
  }

  Future<void> reconnect() async {
    final active = session.activeConnection;
    if (active == null) return;

    // Re-resolve the credential. The session's activeConnection snapshot
    // has lost its runtimePassword to the store-listener overwrite — the
    // store strips runtime passwords on every persisted mutation (table
    // open, column resize, favorite toggle), and the listener pushes that
    // stripped snapshot into the session. Without re-resolution we'd send
    // an empty password and the server would reject the reconnect.
    final credential = await _resolveCredentialWithUnlock(active);
    switch (credential) {
      case CredentialError(message: final m):
        _surfaceReconnectError(m);
        return;
      case CredentialNeedsPassphrase():
        _surfaceReconnectError('Master passphrase required.');
        return;
      case CredentialOk(password: final p):
        session.setActiveConnection(active.copyWith(runtimePassword: p));
    }

    final ok = await session.reconnect();
    if (!ok) return;
    await _loadCatalog(awaitPhase1: false);
  }

  /// Surface a pre-flight failure on the reconnect path. From a `lost`
  /// state we update the banner in place so the workspace stays mounted;
  /// otherwise the existing setError path takes over.
  void _surfaceReconnectError(String message) {
    if (session.status == ConnectionStatus.lost) {
      session.updateLostError(message);
    } else {
      session.setError(message);
    }
  }

  Future<void> refreshCatalog() async {
    await _loadCatalog(awaitPhase1: true);
  }

  Future<List<DbSchema>?> _loadCatalog({required bool awaitPhase1}) async {
    final svc = session.service;
    if (svc == null) return null;
    final schemas = await catalog.load(svc, awaitPhase1: awaitPhase1);
    if (schemas == null) return null;
    if (schemas.length == 1) ui.expandSingleSchema(schemas.first.name);
    return schemas;
  }

  // --- Query messages --------------------------------------------------

  void clearQueryMessages(QueryTab tab) {
    tab.clearMessages();
    final connId = session.activeConnection?.id;
    if (connId != null) store.clearQueryMessages(connId, tab.id);
  }

  // --- Navigation history ---------------------------------------------

  void historyBack() => history.back(_applySnapshot);

  void historyForward() => history.forward(_applySnapshot);

  bool _applySnapshot(NavSnapshot snap) {
    final list = tabsController.tabs;
    final i = list.indexWhere((t) => t.id == snap.tabId);
    if (i == -1) return false;
    tabsController.selectTab(i);
    final tab = list[i];
    if (tab is TableTab && snap.hasTableState) {
      final current = NavSnapshot.table(
        tab.id,
        filter: tab.filter,
        selectList: tab.selectList,
        orderBy: tab.orderBy,
        page: tab.page,
      );
      if (current != snap) {
        unawaited(
          tabsController.loadTablePage(
            tab,
            snap.page ?? 0,
            clauses: TableClauses(
              filter: snap.filter!,
              selectList: snap.selectList!,
              orderBy: snap.orderBy!,
            ),
          ),
        );
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

  /// Drain the AppStore's pending debounced write so a quit while a
  /// mutation is still buffered doesn't lose it.
  Future<void> flush() => store.flush();

  void dispose() {
    store.removeListener(_syncSessionFromStore);
    tabsController.dispose();
    history.dispose();
    catalog.dispose();
    session.dispose();
    ui.dispose();
    eventLog.dispose();
    toasts.dispose();
    store.dispose();
  }
}
