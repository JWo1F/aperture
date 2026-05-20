# dbv — Synthesis & rework plan

Cross-referenced findings from 01-architecture.md, 02-code-quality.md,
03-production-readiness.md. Items marked **★** appear in two or more reports.

## Themes (descending impact)

### A. Data-integrity hazards (must fix before "production")
- **★ ctid-based UPDATE without row-count guard** (Prod #1).
  ctid moves on VACUUM FULL / HOT update; no `affectedRows == 1` assertion;
  no `SELECT … FOR UPDATE`. Silent wrong-row edits possible.
- **★ Non-atomic persistence** (Arch #4, Prod #10).
  `writeAsString` + truncate on every favourite/keystroke/resize. Crash
  mid-write wipes everything. Fix: temp + fsync + rename.
- **★ Multi-statement parser shreds dollar-quotes / E-strings** (Prod #4).
  `CREATE FUNCTION`, `DO $$ … $$`, `E'\n'` are all broken.
- **★ SQL identifier quoting incomplete** (Prod #8, CQ #4).
  Hand-rolled `"$col"` in ~15 call sites; embedded `"` breaks. Centralise.
- **Filter / SELECT / ORDER BY are raw concat** (Prod #2). FK follow values
  are not parameterised. Use `Sql.named` for generated fragments.

### B. Robustness gaps
- **★ Connection-drop / timeout handling absent** (Prod #7). Idle
  disconnect from RDS / Supabase / VPN leaves the app stranded. No
  keepalive, no auto-reconnect, no query timeout, no cancel.
- **★ Plaintext passwords in JSON** (Arch §4, Prod #3). Move to Keychain
  via `flutter_secure_storage`.
- **No logging / no SQL audit trail** (Prod #6). When something fails the
  user has no breadcrumbs. Need a ring-buffer event log.
- **Streaming exports + LIMIT defaults** (Prod #5). Whole result + whole
  rendered string in heap simultaneously. OOM on big tables.
- **Silent error swallowing** (CQ #9, Prod #10). `refreshCatalog`,
  `_loadCatalogPhase1`, `connect` catch broadly with no user signal.

### C. Architecture (unlocks everything else)
- **★ AppState god-object (1129 LOC, 18 concerns, 28 notifyListeners)**
  (Arch #1, CQ implied). Split into 7 narrower notifiers:
  ConnectionRegistry, SessionController, CatalogController, TabsController,
  NavigationHistory, PerConnectionStore, WorkspaceUiState.
- **★ Per-tab state should live on the tab as a ChangeNotifier**
  (Arch §1 expanded). Removes ~220 LOC from AppState; fixes the
  connection-A→B column-width race; tab rebuilds become local.
- **★ Driver types leak into models + ui** (Arch #2, CQ #3).
  `UndecodedBytes` references in `value_format.dart` and `cell_picker.dart`.
  Introduce driver-free `CellValue` sealed DTO at the service boundary;
  replace `dynamic` with `Object?` or `CellValue` throughout.
- **Upward import: services → state** (Arch #3). Move `CellEditValue` to
  `lib/models/cell_edit.dart`. 10 LOC.
- **Repository split** (Arch §3). `PostgresConnection` (lifecycle +
  `runQuery`) vs `TableRepository` (`countRows` / `fetchPage` /
  `applyEdits` / `loadDdl`). Unblocks testing the edit pipeline without
  a live DB.
- **Navigation history holes** (Arch #5). Dead-tab pruning, no `page`
  capture, in-flight `loadTablePage` races; pull into its own notifier
  with per-tab generation counter.

### D. Code-quality wins (mechanical, no behavior change)
- **`Hoverable` widget** (CQ #1): collapses 20× hand-rolled
  `MouseRegion + _hover` widgets, removes ~600 LOC.
- **`Object?` over `dynamic`** (CQ #3): one find/replace across cell-value
  callbacks; analyzer starts catching missed narrowing.
- **`equalityFragment` consolidation** (CQ #4): same function exists in
  AppState and TableView with subtly different output (`BigInt` branch
  forgotten in one). Centralise in `value_format.dart`.
- **`listEquals` (foundation)** (CQ #6): kill `_listEq` + `_sameColumns`.
- **`filenameTimestamp`** (CQ #7): two copies; consolidate.
- **`cell_picker.dart` split** (CQ #2): 1500 LOC / 12 widgets, no new
  abstraction, just file boundaries by kind.
- **`openTable` returns the focused `TableTab`** (CQ #10): kills two
  `lastWhere` casts in `findRowInTable` / `followForeignKey`.
- **Sealed `switch` should be exhaustive** (CQ §7): `_TabState._tabIcon`
  uses `_` default and defeats the analyzer.

### E. Tests (essentially absent — Prod tests section)
Zero coverage on:
- `parseSqlStatements`
- `buildEditStatements` / `_renderUpdate`
- `formatCellValue` (every Pg type + binary fallback)
- `_NavSnapshot` push/apply
- Welcome → connect → load happy-path widget test with a fake service

### F. UX & macOS rough edges (deferable, but flag)
- No window-size restoration, no app menu, no Edit menu Cut/Copy/Paste,
  no quit-confirmation when pending edits exist.
- No arrow-key cell nav in the grid, no Enter-to-edit.
- No "edit existing connection" from welcome screen.
- Welcome panel shows raw exception text; needs triage (SocketException,
  PgException sqlState 28P01/3D000 → friendly messages).
- No "About / version" dialog.

---

## Proposed phased rework

Each phase keeps analyze → test → build green and ships independently.

### Phase 1 — Safety net (data integrity + persistence)
*Highest urgency. ~1-2 days. Touches services + state, no UI changes.*

1. Atomic writes in `ConnectionStore` and `PreferencesStore` (temp + fsync
   + rename; backup corrupt files as `.bak`).
2. `affectedRows == 1` assertion in `applyTableEdits`; transaction-level
   rollback on mismatch; surface "row no longer matches; reload".
3. Run editing transaction at `REPEATABLE READ`.
4. Move passwords to macOS Keychain via `flutter_secure_storage`;
   migrate existing plaintext on first launch.
5. Centralise `quoteIdent(name)` / `qualify(schema, name)`; replace ~15
   hand-rolled `"$col"` sites.
6. Parameterise `_equalityFragment` and FK-follow values via `Sql.named`.

### Phase 2 — Architecture decomposition
*Biggest LOC mover, mechanical. ~2-3 days.*

1. Move `CellEditValue` to `lib/models/cell_edit.dart`; kill services→state
   import.
2. Driver-free `CellValue` DTO at service boundary; `value_format.dart`
   and `cell_picker.dart` lose `package:postgres` import.
3. Split `AppState` into 7 notifiers under `lib/state/`:
   - `connection_registry.dart` (saved connections + persistence)
   - `session_controller.dart` (live PostgresService + status)
   - `catalog_controller.dart` (schemas, columns, FKs, generation)
   - `tabs_controller.dart` (tabs list + active index + open/close)
   - `navigation_history.dart` (snapshots, pruning, generation)
   - `per_connection_store.dart` (favorites, recents, saved queries,
     column widths — debounced flush, per-connection JSON file)
   - `workspace_ui_state.dart` (expanded schemas, sidebar search)
4. Promote `WorkspaceTab` to `ChangeNotifier`; move loading/filter/sort/
   edits/auto-refresh onto the tab itself; UI binds via
   `Provider<TableTab>`. Removes ~220 LOC from AppState.
5. Repository split: `PostgresConnection` + `TableRepository` +
   `Introspector` (last one already exists).

### Phase 3 — Robustness
*~1-2 days.*

1. Connection keepalive (idle `SELECT 1` every 30s); detect socket loss;
   `ConnectionStatus.lost` keeps tabs alive; reconnect banner.
2. Query timeout (default 60s, configurable); CancelRequest on timeout.
3. Streaming exports (rows → IOSink); Cancel button.
4. Default `LIMIT` injection for ad-hoc `runQuery` without LIMIT.
5. Ring-buffer event log + `⌘L` slide-out pane + nightly `.ndjson` file.
6. Friendly connect error messages (SocketException, 28P01, 3D000, etc.)
7. Dollar-quote and E-string aware multi-statement parser; detect
   `BEGIN`/`COMMIT`/`ROLLBACK` and route the whole script through
   `runTx` accordingly.

### Phase 4 — Tests
*~1 day.*

Unit:
- `parseSqlStatements` (dollar-quote, E-string, comments, semicolons in
  strings)
- `buildEditStatements` (literals, DEFAULT, quoting)
- `formatCellValue` (each pg type, binary fallback, citext)
- `equalityFragment`
- Navigation history (push, apply, dead-tab prune, generation race)

Widget:
- Welcome → fake connect → catalog → open table → edit cell → apply
  with a fake `TableRepository`.

### Phase 5 — Code-quality polish
*Mechanical. ~half day.*

1. `Hoverable` widget; migrate 20 sites (-600 LOC).
2. `Object?` over `dynamic` on all cell-value paths.
3. Cell-picker file split.
4. `equalityFragment` consolidation; kill `_listEq`/`_sameColumns`;
   `filenameTimestamp`; `firstWhereOrNull`.
5. Exhaustive `switch` over sealed (`_TabState._tabIcon`).
6. Memoise `aggregatedSingleColumnForeignKeys` / `findUniquePrimaryKeyOwner`.

### Phase 6 — UX & macOS polish (optional, can ship without)

- Window restoration (size + position in PreferencesStore).
- Native app menu + Edit menu Cut/Copy/Paste/Select-All.
- Quit confirmation when pending edits exist on any tab.
- Arrow-key cell nav + Enter-to-edit + Tab/Shift-Tab during edit.
- "Edit connection" from welcome cards.
- About dialog.

---

## Suggested execution order

Phase 1 first (it's the only one whose absence can cost the user actual
data). Then Phase 2 (everything else is harder without the decomposition).
Then Phase 3+4 in parallel as independent commits. Phase 5 last (pure
polish). Phase 6 deferable.

Each phase ends with `flutter analyze → test → build` and a single
focused commit per feature inside the phase, per CLAUDE.md commit
discipline.
