# dbv — Production Readiness Review

Lens: robustness, correctness under failure, security, performance, UX rough edges.

## Tooling baseline

- `flutter analyze` → **No issues found** (1.6 s, ran clean).
- `flutter test` → **1 test, all passing.**

The only test is `test/widget_test.dart` — a single smoke test that pumps `DbvApp` and looks for the string `New Connection`. Coverage of services, state, parsers, exporters, and the cell-edit lifecycle is **zero**. This is the single most exposed surface in the codebase.

---

## Top 10 production blockers (ranked by severity)

### 1. UPDATE statements built by ctid have **no row-count guard and no isolation**

**Where**
- `lib/services/postgres_service.dart:382-393` — `_renderUpdate` builds `WHERE ctid = '(0,5)'::tid` per edit.
- `lib/services/postgres_service.dart:352-366` — `applyTableEdits` runs them in a `runTx` but never asserts `affectedRows == 1` and never holds the rows.

**Why it matters**
- `ctid` is a *physical* row pointer. Any concurrent `UPDATE`, `VACUUM FULL`, `CLUSTER`, or HOT update on the row moves it. The user can then "edit" what they thought was row X and silently update some other row that now occupies `(0,5)`, or update nothing.
- The transaction is `READ COMMITTED` (Postgres default). No `SELECT … FOR UPDATE` was issued when the page was fetched (`fetchTablePage` at line 79-137 is a plain SELECT), so the rows are not locked between page load and apply. Between fetch and apply (potentially many seconds while the user types), arbitrary writers can shift ctids.
- A `runTx` that mass-touches all pending edits will commit partial work whenever `affectedRows` is, say, 0 — `applyTableEdits` returns the sum of affected rows but never raises if a statement updated 0. The grid then reloads (`loadTablePage`) and the user sees their edit "stick" in some cells and silently disappear in others.

**Fix sketch**
- After each `session.execute(sql)` in `applyTableEdits`, assert `result.affectedRows == 1`; on mismatch throw → transaction rolls back, surface a "row no longer matches; reload" message.
- Even better: refuse to edit when the relation has no real PK *and* require `SELECT … FOR UPDATE OF t` (or a snapshot version column) for tables that do. Fall back to ctid only as a last resort and warn the user.
- Consider running the whole tx with `REPEATABLE READ` so the reload at apply time sees a consistent snapshot.

---

### 2. SQL filter, ORDER BY, and SELECT projection are concatenated raw — broken under common inputs and an injection surface

**Where**
- `lib/services/postgres_service.dart:54-66` — `_whereClause` and `_projection` embed user text verbatim.
- `lib/services/postgres_service.dart:79-137` and `fetchAllTableRows` (142-166) splice them into the query.
- `lib/state/app_state.dart:847-855` — `_equalityFragment` builds `"col" = 'value'` by single-quote doubling only — no E-string handling, no backslash escape, no type casting.
- `lib/ui/workspace/table_view.dart:108-120` — same pattern in `_addFilter`.

**Why it matters**
- "Single-user tool" doesn't dodge correctness. A bytea value, a string containing a backslash-N sequence, a numeric column, or any value whose `toString()` doesn't round-trip to a SQL literal will produce a malformed filter — best case a server error, worst case a filter that silently matches the wrong rows.
- The `\` in CSV-pasted values or in JSON values containing `\u` escapes is **not** neutralised. Postgres' `standard_conforming_strings` defaults are version-dependent; the code assumes one.
- The FK-follow path `findRowInTable` (state line 192-203) sends server values straight back as a filter — round-tripping a `UndecodedBytes` value through `toString()` can produce literal `Instance of '…'`.
- It is also a textbook SQL injection surface — yes, single-user, but the user pastes filter clauses from chat / Stack Overflow / their own scripts. Even ignoring malice, "the filter input parses arbitrary SQL" means a stray `; DROP TABLE …` in a paste is one click away from running.

**Fix sketch**
- Don't try to parse user filters — but for the *generated* fragments (FK follow, "Filter: col = value" context menu, `_equalityFragment`), bind values as parameters via `Sql.named`. The driver supports it; the catalog DDL load already uses it.
- For the user-typed `WHERE`/`ORDER BY`/`SELECT`, document this clearly and run them as is — but at minimum strip trailing `;` and reject statements that contain unbalanced quotes before sending. Right now they go straight to the wire and any server error becomes a "page failed to load" toast.

---

### 3. Passwords stored in plaintext JSON

**Where**
- `lib/services/connection_store.dart:36-45` — writes `connections.json` unencrypted.
- `lib/models/connection_config.dart:52-69` — `toJson` serialises `password` verbatim.

**Why it matters**
- macOS sandbox isolates the file per-user-account, but it's still a flat JSON file on disk. Anything running as the same user (Spotlight indexers, Time Machine, malware, accidental sync to iCloud Drive / Dropbox / a shared GitHub repo) reads it.
- The file path is `Application Support/dbv/connections.json` — not under `~/Library/Keychains` and **not** included in the user's expectations about credential storage.
- The CLAUDE.md acknowledges this ("personal use only — passwords are stored in plain text"), but a tool that fronts Postgres credentials should default to using the macOS Keychain. Even the personal user gets bitten the moment they back up their machine somewhere a third party can read.

**Fix sketch**
- Adopt `flutter_secure_storage` (Keychain-backed on macOS) for the password field. Keep the rest of the config in JSON keyed by connection id; resolve the password at connect time.
- If you don't want a new dependency, call the macOS Keychain directly through a method channel (small Swift shim, no extra entitlements needed beyond the existing keychain default).
- Set the file permissions to 0600 in the meantime. Currently `File.writeAsString` uses the OS default (0644 in the user container).

---

### 4. Multi-statement script handling has no transaction control and silently swallows partial work

**Where**
- `lib/ui/workspace/query_editor.dart:132-151` — `_runAll` parses statements, runs them one by one via `runQuery(sqlOverride: …)`, stops on the first error.
- `lib/services/postgres_service.dart:306-347` — `runQuery` catches `ServerException` and returns a `QueryResult.failure`, hiding the failure from the caller's exception handling and letting the next statement try to run after a (suppressed) connection-state surprise.
- `lib/services/sql_statements.dart` — the parser doesn't understand:
  - dollar-quoted strings (`$$ … $$`, `$tag$ … $tag$`) — used in every `CREATE FUNCTION` / `DO` block. A `;` inside the function body will be treated as a statement separator and split the script.
  - PostgreSQL escape strings (`E'…'`) — `\'` inside an E-string will not close the quote in Postgres but does in this parser.
  - `BEGIN; … COMMIT;` blocks specifically — they're sent as separate statements, so a mid-script error after `BEGIN` leaves the user in an in-progress transaction with no UI affordance to rollback.

**Why it matters**
- A user pasting any non-trivial DDL (function bodies, COPY, DO blocks) gets it shredded.
- A `BEGIN` followed by a failing statement leaves the connection in `aborted` state — every subsequent statement returns `current transaction is aborted, commands ignored until end of transaction block`, and the user has no Rollback button. They have to disconnect.

**Fix sketch**
- Extend the parser to track dollar-quote tags (push `$tag$` → ignore until matching `$tag$`) and E-strings (treat `\` as an escape inside).
- When `_runAll` detects any of `BEGIN`, `START TRANSACTION`, `COMMIT`, `ROLLBACK`, `SAVEPOINT` in the script, fall back to sending the **entire** text through `Connection.execute` as a simple query — the postgres package's `execute` accepts that, but you'd need to use the simple-query path. Or wrap the whole script in `_conn.runTx` so a mid-script failure rolls everything back.
- Surface "transaction state" in the UI footer (a small badge that lights up when the server reports `T`/`E` ReadyForQuery status — the driver exposes it).

---

### 5. `fetchAllTableRows` and the exporter load entire result sets into memory — no streaming, no progress, no cancel

**Where**
- `lib/services/postgres_service.dart:142-166` — `fetchAllTableRows` materialises every row in `rows = result.map((r) => r.toList()).toList()`.
- `lib/services/exporter.dart:13-23` — `ExportFormat.render(result)` builds a single `String` in memory before `writeAsString`. CSV and Markdown both walk the entire `result.rows` list and build a `StringBuffer` containing the full output.
- `lib/state/app_state.dart:1077-1086` — `runQuery` for ad-hoc SQL has no `LIMIT` injection; pasting `SELECT * FROM events` against a billion-row table will OOM the Dart isolate.

**Why it matters**
- The user already has the "Export all filtered rows" affordance (`table_view.dart:202-210`) — for a 5 M row table that's ~5 M Dart `List<dynamic>` allocations plus a stringification pass. Both the result set and its rendered string live in the heap at the same time during file write.
- There's no cancel: once `fetchAllTableRows` is in flight, the user can't abort. `Connection.close()` would interrupt, but `postgres_service.close()` is only wired to disconnect, which destroys all UI state.
- No "this will fetch N rows, ~M MB — continue?" guard. The export dialog (`export_dialog.dart:233-237`) shows `~$allCount rows (re-fetched from the database)` but doesn't tell the user that the entire result is going through memory.

**Fix sketch**
- For raw query results: enforce a default `LIMIT` (configurable, default 10 000), or detect statements without LIMIT and wrap them in a CTE that adds one. Show a banner "Truncated to 10 000 rows" when applied.
- For exports: switch to a streaming pipeline. The postgres driver returns a `Result` that is iterable; render rows directly to an `IOSink` opened against the destination `File`. The format interface becomes `Future<void> writeStream(IOSink, Stream<List<dynamic>>)`.
- Add a `Cancel` button on the export dialog that closes the result stream.

---

### 6. No logging, no error breadcrumbs, no way to see the SQL that ran

**Where**
- Searched the codebase for `print`, `log`, `developer.log` — nothing. Every `catch` block either swallows (`connection_store.dart:31-34`, `app_state.dart:491-493`) or wraps the message into a `QueryResult.failure`.
- `lib/services/postgres_service.dart:130-136`, `342-346` — `ServerException.message` is captured (a short string like "relation does not exist") but the **statement that produced it** is never logged. So a failure in the auto-refresh path (`app_state.dart:872-882`) is shown as a red row with "syntax error" and no SQL.
- `_loadCatalogPhase1` (line 462-500) calls `catch (_)` and silently leaves the catalog in a partial state.

**Why it matters**
- When the app misbehaves there is no audit trail. The user's only debug surface is "open the connection again and hope it works."
- For an editing tool, an *event log* of every UPDATE / DDL submitted with a copyable timestamp is essentially required — the user needs to be able to answer "what did I do at 14:32?"

**Fix sketch**
- Add a ring-buffer log in `AppState` keyed by `(timestamp, kind, sql, elapsed, error?)`. Render it as a slide-out "log" pane (could be hidden behind a ⌘L shortcut). Persist to `Application Support/dbv/log/YYYY-MM-DD.ndjson`.
- Replace `catch (_)` with `catch (e, st)` and at minimum `developer.log` it under a `dbv` zone.
- Display the actual SQL inside `QueryResult.failure` UI — currently `results_grid.dart:513-519` shows only the error string.

---

### 7. No connection-drop / timeout handling — first failure leaves the app in an unrecoverable "not connected" state

**Where**
- `lib/services/postgres_service.dart:41-47` — `_conn` throws `StateError('Not connected')` on closed connection.
- `lib/state/app_state.dart:1077-1086` — `runQuery` only checks `_service == null`; if the connection is open *from the app's perspective* but the server killed it, the next call throws and the catch in `runQuery` returns `QueryResult.failure` with an opaque message. The next user action throws again. Nothing reconnects.
- No `connectTimeout` after the initial connect; no query timeout at all. `Connection.open` uses 10 s, but `execute` uses none.
- The `postgres` package's `Connection` has no built-in keep-alive ping configured here. After a NAT timeout (corporate VPN, cloud DB idle disconnect) the socket is dead and the user sees "Not connected" on every action.
- `disconnect()` is the only recovery path; it nukes tabs (`app_state.dart:416`) and forces the user to re-open everything.

**Why it matters**
- This is the single most common production failure mode for a DB client.
- Cloud Postgres providers (RDS, Supabase, Neon) routinely close idle connections. Wi-Fi roaming kills the socket. The current code leaves the user stranded with a status bar that reads `Disconnected` but doesn't tell them why or invite them to reconnect.

**Fix sketch**
- Add an `applicationName: 'dbv'` (already done) + a periodic `SELECT 1` health check on idle connections (e.g. every 30 s).
- On any `SocketException` / `PostgreSQLException`-as-connection-lost during `runQuery` / `fetchTablePage`, transition status to a new `ConnectionStatus.lost`, *keep tabs mounted*, show a banner "Connection lost — reconnect", and try to re-open the connection without flushing the workspace.
- Add a query timeout (configurable, default 60 s) by racing the `execute` against `Future.delayed`. On timeout, send a cancellation request (Postgres protocol-level CancelRequest) — the driver exposes this on newer versions.

---

### 8. SQL identifier quoting is incomplete — table/column names with embedded quotes silently break, and reserved-word schemas break

**Where**
- `lib/services/postgres_service.dart:302` — `_quoteIdent` only doubles `"`. It's only used in `loadTableDdl`.
- Everywhere else uses `table.qualifiedName` (which I'd expect to render `"schema"."name"` but worth verifying) and *manually written* `"$column"` in many places: `app_state.dart:848-854`, `table_view.dart:111-117`, `postgres_service.dart:388`, `392`. None of these escape embedded `"`.
- A column named `weird"name` (legal in Postgres) interpolated as `"weird"name"` produces a syntax error or, worse, a successful but wrong parse.

**Why it matters**
- A user who connects to a third-party database (some ORM-generated schemas in the wild use mixed-case, embedded quotes, or Unicode) will see random failures with no clear cause.
- It also means the "edit a cell" flow can fail with a syntax error and the user gets a confusing message — the column name is *theirs* (they just clicked it).

**Fix sketch**
- Centralise: one `String quoteIdent(String name)` that doubles `"`, wraps in `"…"`, and rejects null bytes. Replace every hand-rolled `"$col"` with `quoteIdent(col)`. The fix is mechanical (~15 call sites).
- Same for schema: `"$schema"."$name"` should always flow through a single `qualify(schema, name)` helper.

---

### 9. Auto-refresh races with user edits and pagination — and a closed tab still fires its timer briefly

**Where**
- `lib/state/app_state.dart:872-882` — `setTableAutoRefresh` creates a `Timer.periodic`. The tick checks `tab.loading || tab.applying || tab.hasEdits` and skips if any are true.
- `lib/state/app_state.dart:895-918` — `loadTablePage` *clears* `tab.edits` unconditionally on entry. Auto-refresh is the only thing that races against this, but a hand-issued refresh button or a header-click sort also clears edits.

**Why it matters**
- The "skip while editing" guard checks `hasEdits` only at the moment of tick — a user who clicks "Sort by created_at" while editing has their edits wiped (sort calls `loadTablePage` which calls `tab.edits.clear()`). That's not auto-refresh, but it's the same underlying foot-gun. The user expects edits to be preserved across sorts.
- More subtle: between `setTableFilter`/`setTableSelect`/`setTableOrder` and the next `loadTablePage`, the ctid for a given row index changes. Pending edits keyed by `(row, column)` indices now point at a *different* row's ctid. Right now this is masked because edits are cleared on every reload, but the clear is itself a UX bug.
- `_cancelAutoRefreshFor(tabId)` is called from `closeTab`, but if the tick has already started the closure can still hit `loadTablePage` for a tab that's being removed (no `_tabs.indexOf` check in `loadTablePage`).

**Fix sketch**
- Preserve `tab.edits` across filter/sort/select changes that don't change the row identity (i.e. anything other than `pageSize`/`page`/`filter`-affecting-row-membership). Re-key the edits by their *ctid* (already known at edit time) and on reload re-locate the rows by ctid before discarding.
- In the periodic tick closure, snapshot the tab reference *and* assert it's still in `_tabs` before calling `loadTablePage`. Simpler still: store the tab id, not the tab, and look it up.

---

### 10. First-run, schema-load and tab-survival edge cases produce silent failures

**Where**
- `lib/state/app_state.dart:443-457` — `_loadCatalogPhase0` only loads schemas; phase 1 (columns, FKs, indexes, enums, domains) is fired-and-forgotten and a failure leaves the catalog half-loaded (`catch (_)` line 491). The user sees a working sidebar but no FK icons, no cell-picker type info, no "Find row" actions, and **no error indicator** beyond `_catalogPhase1Loading` being stuck off.
- `app_state.dart:398-403` — connect failure sets `connectionError = e.toString()` (raw exception text). The welcome panel's `_ErrorBox` (`app_shell.dart:875-910`) prints it verbatim — `PgException(message: …, sqlState: 28P01, …)` or a raw `SocketException` go straight to the user.
- `app_state.dart:393` — on a successful connect, `_hydrateRecents(stamped)` runs *before* the catalog is fully loaded, so saved "recent tables" that no longer exist disappear silently. There's no indication; the user just doesn't see them.
- `app_state.dart:73-93` — `_hydrate` swallows all errors from `_store.load()` (the store itself catches and returns `[]`). A corrupt `connections.json` results in "no connections, and no idea why" with no recovery path.
- `app_state.dart:396` — `unawaited(_loadCatalogPhase1(gen))` is non-awaited at connect time, but the **first paint after connect** depends on catalog data for the cell picker (`results_grid.dart:317` `widget.columnMeta`). Until phase 1 lands, every NULL cell falls through to the default text picker.

**Why it matters**
- The user's mental model is "the app failed to load my server", but the actual message is a stack-trace fragment.
- Corrupt connections.json (e.g. partial write during crash, since `save` is non-atomic) wipes the user's saved list with no warning.

**Fix sketch**
- Replace the raw `e.toString()` with a triage step: SocketException → "Can't reach `$host:$port`. Check VPN / firewall."; PgException with sqlState 28P01 → "Wrong password for user `$username`."; 3D000 → "Database `$db` does not exist."
- `connection_store.save` should write to a tempfile + rename atomically (`file.rename`) so partial writes never corrupt the source of truth. On load, if `jsonDecode` fails, preserve the broken file as `connections.json.bak` instead of returning `[]`.
- Add a phase-1 retry button next to the catalog-loading indicator in the sidebar. Currently `_catalogPhase1Loading` going false on failure looks identical to it going false on success.

---

## Other issues worth flagging (not in the top 10 but cheap to fix)

### Tests

The test surface is essentially empty. Risky areas with zero coverage:

- `parseSqlStatements` (lib/services/sql_statements.dart) — table-stakes parser tests for strings, comments, dollar-quotes, E-strings.
- `buildEditStatements` / `_renderUpdate` — pure, easy to test, no DB needed.
- `formatCellValue` — every postgres type plus the binary fallback path.
- `_NavSnapshot` history push/apply logic in `AppState`.
- Sealed-class exhaustiveness: `Workspace._content` (workspace.dart:65-72) is exhaustive but there's no test that asserts the analyzer keeps it that way after adding a new tab type.

### macOS

- **`network.server` entitlement is in Debug only** (`macos/Runner/DebugProfile.entitlements:9-10`) but **not** in `Release.entitlements`. The Debug build can listen on a TCP socket (Flutter's hot-reload needs that), the Release build can't — fine. But verify no plugin needs `network.server` at runtime in Release; if any do, they fail silently in shipped builds.
- No Apple Developer ID signing / notarization config visible. A user dragging the .app from a download will see Gatekeeper's "damaged" warning.
- `MainFlutterWindow.swift` has only two method channel handlers (`startDrag`, `toggleZoom`). There is no `windowShouldClose`, no menu bar customization, no NSDockMenu. ⌘W will close the only window which terminates the app — no quit confirmation when there are unapplied edits.
- No application menu — the default Flutter menu shows "DbvApp" with empty Edit menu. Cut/Copy/Paste/Select-All shortcuts inside TextFields work only via Flutter's intrinsic bindings; out of TextField focus they don't.
- `WindowManipulator.hideTitle()` is called but the window title is still set to `'DBV'` via `MaterialApp` — this is benign but the toolbar `_BrandMark` reads `'dbv'` (lowercase) while the welcome screen reads `'DBV'` and the macOS title would say `'DBV'`. Minor branding inconsistency.
- No window restoration: window size/position are not persisted (`PreferencesStore` (lib/services/preferences_store.dart) only saves `brightness`). Every launch is at the default size in the default position.
- ⌘[ / ⌘] are intercepted at the `HardwareKeyboard` level (`app_shell.dart:49-62`), which means they steal navigation history from `TextField`s where the user might expect to move the caret — that's documented in a comment but still surprising in the SQL editor.
- No support for two windows / two databases at once — the sealed-state design fights this; consider whether shipping with that limitation is acceptable.

### Keyboard navigation in the grid

- No arrow-key cell navigation (`_handleKey` in results_grid.dart:238-253 only handles Esc + ⌘C). The user must use the mouse to pick the next cell.
- No Enter-to-edit on the selected cell. The cell picker is double-click-only — discoverable only via the right-click menu's shortcut hint (`⏎⏎`).
- No Tab / Shift-Tab to move between cells while editing.
- The grid focus is requested only on first cell click (`_selectCell` at line 218); before that, ⌘C doesn't work.
- No row selection ("select row 5"), only cell selection. "Copy row" isn't there.

### CSV / Markdown / clipboard edge cases

- `MarkdownFormat._writeRow` (`exporter.dart:114-122`) renders cell widths in **characters**, not in display-width-aware code points — Unicode-wide CJK characters misalign in plain editors. Acceptable, but flag it.
- `MarkdownFormat._escape` replaces `\n` with `<br>` (line 137-142) — fine for GFM but ugly in non-GFM Markdown.
- CSV NULL is rendered as empty string (`exporter.dart:57`). Some tools can't distinguish empty-string from NULL. No option to render NULL as `\N` (Postgres COPY default) or `NULL`. The export dialog has no option for this.
- The clipboard copy path (`export_dialog.dart:100-104`) renders into a single Dart `String` and calls `Clipboard.setData`. On macOS, very large strings (multi-MB) can hang the UI; there's no size guard.

### Welcome screen

- No way to **edit** an existing connection from the welcome cards — only connect or "New connection". Editing is buried behind the connection menu (`connection_menu.dart`) once you're connected.
- No way to **import** existing connections (e.g. from a pgpass file). Saw no UI for it.

### Cell picker

- `_initialMoment` (cell_picker.dart:255-283) parses time-of-day with a regex but accepts hours up to 99 silently (clamped later in `_TimeInputState._emit`, line 1334-1340). Out-of-range typed values are silently clamped on save without informing the user.
- `_kindFor` (line 183-223) treats `array` and `dt.endsWith('[]')` as JSON. Editing a Postgres array via the JSON editor will produce SQL like `'[1, 2, 3]'::unknown` which Postgres usually accepts via coercion, but multi-dimensional arrays and arrays of composite types break — the user gets a server error with no hint.
- `_literal` in `postgres_service.dart:403-406` quotes everything as text and trusts coercion. For `bytea`, `json[]`, and custom enums this often works, but for `numeric` with locale-sensitive separators or `interval` it silently produces the wrong value.
- The picker's `Save` button only enables when `_isDirty` (line 581) — fine — but there is no "Save and edit next cell" affordance, so editing a column of 50 rows means 50 round-trips of click → ⌘↵.

### Performance

- `_autoWidth` (`results_grid.dart:163-189`) layouts up to 50 cells per column for default sizing on every page load. For very wide tables (~100 columns) this is 5000 `TextPainter.layout()` calls per page — measurable on the first paint.
- `ResultsGrid` rebuilds on every parent rebuild because `_syncWidths` (line 191-199) runs whenever `result` identity changes — and `loadTablePage` always assigns a new `QueryResult` (postgres_service.dart:123-129). The saved widths are preserved via the map, but the auto-width loop runs for any column that lacks a saved width.
- Sidebar (not read here but referenced) likely traverses all schemas on every notifyListeners — worth profiling on a database with 1000+ relations.

### Security — minor

- The toolbar's `_windowChannel` method call (`app_shell.dart:128`) listens to platform method results but doesn't await — fine in practice, but a hung native call would build up futures.
- `Sql.named` is only used in two places (`postgres_service.dart:201`, DDL load). Bind-parameters are the better default.
- Process arguments / environment variables — nothing is read from `Platform.environment`, no secret can leak via env. Good.
- No telemetry / analytics. Good.
- No HTTP / WebSocket clients. Network is purely Postgres. Good.

### Observability / UX

- The status bar at the bottom of the shell (`app_shell.dart:912-952`) shows connection summary and schema count — no "currently running query" indicator, no "auto-refresh active on N tabs" indicator.
- No "About" / version dialog. `pubspec.yaml` is `1.0.0+1` and that version is invisible to the user.
- No crash dialog. An unhandled exception in `runApp` will silently kill the app on macOS (or show the Flutter error overlay in debug).
- No "Reset" / "Clear app state" command. If `connections.json` corrupts, the user has to find Application Support manually.

---

## Summary

The MVP is solid in shape but the **safety net is thin**. The three things I'd insist on before calling this "shippable" are:

1. **Row-identity safety on UPDATE** (blocker #1) — every other concern is recoverable, this one silently corrupts data.
2. **Connection-drop survival + an event log** (blockers #6 + #7) — without these, the user has no way to diagnose anything.
3. **Some tests** — at minimum: `parseSqlStatements`, `buildEditStatements`, `formatCellValue`, `_NavSnapshot`, and a widget test for the welcome → connect → load flow with a fake `PostgresService`. The current single smoke test is not load-bearing.

Everything else can be triaged.

## Files referenced

- `/Users/jwo1f/work/jwo1f/dbv/dbv/lib/services/postgres_service.dart`
- `/Users/jwo1f/work/jwo1f/dbv/dbv/lib/services/connection_store.dart`
- `/Users/jwo1f/work/jwo1f/dbv/dbv/lib/services/sql_statements.dart`
- `/Users/jwo1f/work/jwo1f/dbv/dbv/lib/services/exporter.dart`
- `/Users/jwo1f/work/jwo1f/dbv/dbv/lib/services/introspector.dart`
- `/Users/jwo1f/work/jwo1f/dbv/dbv/lib/state/app_state.dart`
- `/Users/jwo1f/work/jwo1f/dbv/dbv/lib/state/workspace_tab.dart`
- `/Users/jwo1f/work/jwo1f/dbv/dbv/lib/models/connection_config.dart`
- `/Users/jwo1f/work/jwo1f/dbv/dbv/lib/models/value_format.dart`
- `/Users/jwo1f/work/jwo1f/dbv/dbv/lib/ui/app_shell.dart`
- `/Users/jwo1f/work/jwo1f/dbv/dbv/lib/ui/workspace/results_grid.dart`
- `/Users/jwo1f/work/jwo1f/dbv/dbv/lib/ui/workspace/table_view.dart`
- `/Users/jwo1f/work/jwo1f/dbv/dbv/lib/ui/workspace/query_editor.dart`
- `/Users/jwo1f/work/jwo1f/dbv/dbv/lib/ui/workspace/workspace.dart`
- `/Users/jwo1f/work/jwo1f/dbv/dbv/lib/ui/cell_picker/cell_picker.dart`
- `/Users/jwo1f/work/jwo1f/dbv/dbv/lib/ui/connection/connection_dialog.dart`
- `/Users/jwo1f/work/jwo1f/dbv/dbv/lib/ui/export/export_dialog.dart`
- `/Users/jwo1f/work/jwo1f/dbv/dbv/lib/ui/edits/pending_edits_modal.dart`
- `/Users/jwo1f/work/jwo1f/dbv/dbv/macos/Runner/MainFlutterWindow.swift`
- `/Users/jwo1f/work/jwo1f/dbv/dbv/macos/Runner/DebugProfile.entitlements`
- `/Users/jwo1f/work/jwo1f/dbv/dbv/macos/Runner/Release.entitlements`
- `/Users/jwo1f/work/jwo1f/dbv/dbv/test/widget_test.dart`
