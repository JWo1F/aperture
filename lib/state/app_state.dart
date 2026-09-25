import 'dart:async';

import '../models/connection_config.dart';
import '../models/db_object.dart';
import '../models/log_event.dart';
import '../models/value_format.dart';
import '../services/db_service.dart';
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

/// Callback the UI installs to confirm an action that would discard staged
/// cell edits. Resolves true to go ahead. [action] completes the sentence
/// "…discards them".
typedef DiscardEditsRequest =
    Future<bool> Function({
      required int pending,
      required String title,
      required String action,
      required String proceedLabel,
    });

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
  AppState({AppStore? store})
    : store = store ?? AppStore() {
    this.store.addListener(_syncSessionFromStore);
    this.store.onSaveFailed = _reportSaveFailure;
  }

  /// A failed write means nothing the user does this session will be there
  /// next launch, so it has to be said out loud once rather than logged
  /// where no one is looking. Repeats are swallowed: the debounce retries
  /// on every subsequent mutation, and a full disk would otherwise raise a
  /// sticky toast per keystroke.
  bool _reportedSaveFailure = false;

  void _reportSaveFailure(Object error) {
    eventLog.add(
      LogEvent(
        timestamp: DateTime.now(),
        kind: LogEventKind.error,
        error: 'Could not save store.json: $error',
      ),
    );
    if (_reportedSaveFailure) return;
    _reportedSaveFailure = true;
    toasts.error(
      'Preferences, connections and saved queries are not being written '
      'to disk. Changes made now will be lost on the next launch.\n\n$error',
      title: 'Cannot save settings',
    );
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

  /// Set by the UI at startup. Consulted before anything that tears the
  /// workspace down with staged edits in it.
  DiscardEditsRequest? onConfirmDiscardEdits;

  /// True when it is safe to destroy every open tab. Asks the user first if
  /// there is un-applied work; with no UI wired, allows it (the state layer
  /// must not deadlock on a missing callback).
  Future<bool> _mayDiscardWorkspace({
    required String title,
    required String action,
    required String proceedLabel,
  }) async {
    final pending = tabsController.unappliedEditCount;
    if (pending == 0) return true;
    final ask = onConfirmDiscardEdits;
    if (ask == null) return true;
    return ask(
      pending: pending,
      title: title,
      action: action,
      proceedLabel: proceedLabel,
    );
  }

  late final TabsController tabsController = TabsController(
    session: session,
    catalog: catalog,
    history: history,
    store: store,
    toasts: toasts,
  );

  /// Keeps the session's config snapshot in step with the store, and deals
  /// with the two edits that make the snapshot and the live socket disagree.
  ///
  /// Pushing the new config in blindly used to leave the sidebar hero and
  /// the connection pill naming a database while every query still went to
  /// the old one — two sources of truth for "where am I connected", with
  /// the UI showing the wrong one.
  void _syncSessionFromStore() {
    final active = session.activeConnection;
    if (active == null) return;
    final fresh = store.connectionById(active.id);

    if (fresh == null) {
      // The active connection was deleted from under us. Nothing can be
      // persisted against it any more, so keeping the socket open would
      // silently drop every favourite, recent and saved query from here on.
      if (session.status != ConnectionStatus.disconnected) {
        unawaited(_disconnectNow());
      }
      return;
    }

    if (identical(fresh, active)) return;
    final retargeted = !fresh.sameTarget(active);
    session.setActiveConnection(fresh);
    if (retargeted) _retarget(fresh);
  }

  /// The user edited the active connection's address. Re-open against it so
  /// the workspace and the socket agree — unless there is staged work,
  /// which must not be silently re-pointed at a different database.
  void _retarget(ConnectionConfig fresh) {
    if (session.status == ConnectionStatus.disconnected ||
        session.status == ConnectionStatus.error) {
      return;
    }
    final pending = tabsController.unappliedEditCount;
    if (pending > 0) {
      toasts.warning(
        'This connection now points somewhere else, but $pending staged '
        'change${pending == 1 ? '' : 's'} still belong${pending == 1 ? 's' : ''} '
        'to the open session. Apply or reset them, then reconnect.',
        title: 'Reconnect pending',
        duration: const Duration(seconds: 8),
      );
      return;
    }
    toasts.info(
      fresh.engine == DbEngine.sqlite ? fresh.filePath : fresh.database,
      title: 'Reconnecting',
    );
    unawaited(reconnect());
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
    // Switching connections closes every tab, so ask before it costs the
    // user staged work. Reconnecting to the one already open doesn't.
    if (config.id != session.activeConnection?.id &&
        !await _mayDiscardWorkspace(
          title: 'Switch connection?',
          action: 'Opening ${config.name}',
          proceedLabel: 'Switch anyway',
        )) {
      return;
    }
    // Resolve the credential BEFORE touching the workspace. This step can
    // fail on its own — a locked vault, a missing `op` binary, a connection
    // saved without a password — and none of those are a reason to throw
    // away the tabs and history of the session that is still live.
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

    // Past here the old connection is closed either way, so its tabs go
    // with it whether or not the new one opens.
    tabsController.clear();
    history.clear();

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
    if (!await _mayDiscardWorkspace(
      title: 'Disconnect?',
      action: 'Disconnecting',
      proceedLabel: 'Disconnect anyway',
    )) {
      return;
    }
    await _disconnectNow();
  }

  /// Tear-down without the prompt, for the paths that have already decided
  /// (a deleted connection, an app that is quitting).
  Future<void> _disconnectNow() async {
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
  // --- Schema object definitions --------------------------------------

  /// Fetches a schema object's `CREATE` statement and opens it in a new query
  /// tab named [name]. The result is dropped if the connection changed while
  /// it was in flight — it would otherwise land in the next database's
  /// workspace.
  Future<void> openDefinition(
    String name,
    Future<String> Function(Introspector) load,
  ) async {
    final service = session.service;
    if (service == null) return;
    try {
      final ddl = await load(service.introspector);
      if (session.service != service) return;
      tabsController.newQueryTab(name: name, sql: ddl);
    } catch (e) {
      if (session.service != service) return;
      toasts.error('$e', title: "Couldn't load the definition of $name");
    }
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

  // --- Uncaught failures ----------------------------------------------

  String? _lastUncaught;

  /// Record a failure that escaped a framework callback or an unawaited
  /// future. Without this the only trace is a debug-console print, which
  /// nobody is watching in a release build.
  ///
  /// Every failure lands in the event log, which is bounded. Only a *new*
  /// message also raises a toast: error toasts are sticky, and something
  /// throwing once per frame would otherwise bury the UI under an unbounded
  /// stack of identical cards.
  void reportUncaught(Object error, StackTrace? stack) {
    final message = error.toString();
    eventLog.add(
      LogEvent(
        timestamp: DateTime.now(),
        kind: LogEventKind.error,
        connectionName: session.activeConnection?.name,
        error: stack == null ? message : '$message\n$stack',
      ),
    );
    if (message == _lastUncaught) return;
    _lastUncaught = message;
    toasts.error(message, title: 'Unexpected error');
  }

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
