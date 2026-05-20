# dbv — Architecture review

Scope: state shape, module boundaries, dependency direction, persistence safety,
threading. ~13k LOC, single root `ChangeNotifier`, two-layer cake
(`models` + `services` ← `state` ← `ui`). MVP is healthy; the cliffs below
are the ones I'd straighten before treating the app as production-shaped.

---

## Top 5 problems, ranked by impact

1. **`AppState` is a 1129-line god-object** that owns 18+ unrelated concerns
   behind one `notifyListeners`. Every UI rebuild for any reason fans out to
   every consumer. (`lib/state/app_state.dart`)
2. **`postgres` driver types leak into `lib/models` and `lib/ui`.**
   `UndecodedBytes` / `ServerException` appear in `models/value_format.dart`
   and `ui/cell_picker/cell_picker.dart`. The driver is a transitive
   dependency of the cell picker, which is wrong direction.
3. **Upward dependency from services to state.**
   `services/postgres_service.dart:6` imports `state/workspace_tab.dart` so it
   can consume `CellEditValue`. Services should not know what a tab is.
4. **Persistence is unsafe across crashes.** `ConnectionStore.save` is
   `file.writeAsString(jsonEncode(...))` (no temp-file + rename, no fsync)
   and is called on every favourite toggle, recent-table update, saved-query
   autosave keystroke, and column-resize debounce tick. A crash mid-write
   wipes the entire connection set including saved queries.
5. **`_NavSnapshot` undercounts navigable state**: no page index, no edits
   guard, no selection. The "back" stack also has tab-lifecycle race holes
   (dead-tab IDs persist after `closeOtherTabs` / `closeAllTabs`; reordering
   would break entirely if/when it's added).

The rest of the document expands these and adds smaller findings.

---

## 1. `AppState` decomposition

### Responsibility audit

Counted from `lib/state/app_state.dart`:

| # | Concern | Fields / methods (line refs) |
|---|---|---|
| 1 | Theme palette | `_brightness`, `setBrightness`, `_persistPrefs` (33–56) |
| 2 | Saved-connection list | `_connections`, `add/update/removeConnection`, `_persist` (58–95, 340–360) |
| 3 | Live session | `_service`, `_activeConnection`, `_status`, `_connectionError`, `connect`, `disconnect` (97–105, 364–420) |
| 4 | Catalog (introspection) | `_catalog`, `_catalogGeneration`, `_catalogPhase1Loading`, `_loadCatalogPhase0/1`, `refreshCatalog` (111–500) |
| 5 | Schema-tree UI state | `_expandedSchemas`, `toggleSchema`, `_sidebarSearch` (125–217) |
| 6 | FK / PK lookups | `findForeignKey`, `findPrimaryKeyOwner*`, `aggregatedForeignKeys` (136–179) |
| 7 | Recent tables | `_recents`, `_trackRecent`, `_persistRecents`, `_hydrateRecents` (221–256) |
| 8 | Tab list + active index | `_tabs`, `_activeTabIndex`, `selectTab`, `closeTab*`, `closeAllTabs` (208–693) |
| 9 | Navigation history | `_navHistory`, `_historyIndex`, `_pushSnapshot`, `historyBack/Forward`, `_applySnapshot` (266–336) |
| 10 | Saved queries | `savedQueries`, `_persistQuery`, `renameQuery`, `deleteSavedQuery`, `duplicateSavedQuery`, `openSavedQuery` (539–645) |
| 11 | Favourites | `isFavorite`, `toggleFavorite`, `favoriteTables` (724–757) |
| 12 | Schema tab actions | `openSchema`, `reloadSchema` (696–772) |
| 13 | Table tab open + page load | `openTable`, `loadTablePage`, `refreshTable` (774–918) |
| 14 | Column-width persistence | `_widthSaveTimer`, `_pendingWidths`, `persistColumnWidth` (799–828) |
| 15 | Auto-refresh timers | `_autoRefreshTimers`, `setTableAutoRefresh`, `_cancelAutoRefresh*` (857–893) |
| 16 | Filter / select / sort / order mutators | `setTableSelect/Filter/Order`, `cycleTableOrder`, `setColumnSort`, `appendTableFilter` (938–1040) |
| 17 | Cell editing | `setCellEdit`, `revertCellEdit`, `resetTableEdits`, `previewEditStatements`, `applyTableEdits` (989–1075) |
| 18 | Query execution | `runQuery`, `fetchAllForExport`, `findRowInTable`, `followForeignKey` (192–203, 834–845, 922–933, 1077–1086) |

Every one of these calls `notifyListeners()` against the same root. Counts:
~28 `notifyListeners` invocations, 15 `context.watch<AppState>()` /
`context.read<AppState>()` call sites across the UI. Touching a cell edit
rebuilds the sidebar; toggling a schema in the tree rebuilds the workspace
tab strip. The `IndexedStack` in `workspace.dart:52` papers over this by
keeping children mounted, but they still rebuild.

### Concrete decomposition

I'd split `AppState` into 7 narrower notifiers/services, glued by a thin
`AppState` whose only job is to own the dependency graph and react to
connection changes. All providable via `MultiProvider` so widgets `watch` the
smallest unit they actually care about.

```
ChangeNotifierProvider(AppState)                       // tiny: brightness + active connection id
├── ChangeNotifierProvider(ConnectionRegistry)         // ~150 LOC
├── ChangeNotifierProvider(SessionController)          // owns PostgresService + status
├── ChangeNotifierProvider(CatalogController)          // owns DatabaseCatalog + generation
├── ChangeNotifierProvider(TabsController)             // owns _tabs + _activeTabIndex
├── ChangeNotifierProvider(NavigationHistory)          // owns _navHistory
├── ChangeNotifierProvider(PerConnectionStore)         // favorites, recents, saved queries, column widths
└── ChangeNotifierProvider(WorkspaceUiState)           // _expandedSchemas, _sidebarSearch
```

Migration map (every field/method above gets exactly one new home):

| New file | Receives |
|---|---|
| `state/session_controller.dart` | Concerns 3 + theme listener; exposes `Stream<PostgresService?>` |
| `state/catalog_controller.dart` | Concerns 4 + 6; subscribes to `SessionController.connectionChanged` to bump generation |
| `state/tabs_controller.dart` | Concerns 8 + 12 + 13 + 16 + 17 + 18; tab mutators stay close to the tab list |
| `state/navigation_history.dart` | Concern 9; listens to `TabsController.removed` to prune dead snapshots eagerly (today they accumulate) |
| `state/per_connection_store.dart` | Concerns 7 + 10 + 11 + 14; one debounced disk write per dirty field |
| `state/workspace_ui_state.dart` | Concern 5 (purely view-side, no need to be in any of the above) |
| `state/app_state.dart` | Brightness + active-connection id only — ~100 lines |

Once split, the call sites in `lib/ui/sidebar/sidebar.dart:32`,
`lib/ui/workspace/table_view.dart:27`, etc. switch from
`context.watch<AppState>()` to `context.watch<CatalogController>()` or
`context.watch<TabsController>()`, so a column-width persist tick no longer
rebuilds the connection menu.

Additional benefit: `TabsController.tabs` becomes a `ChangeNotifier`-of-list
that the `IndexedStack` in `workspace.dart:52` can watch directly — today it
re-mounts on every unrelated `notifyListeners` because everything routes
through one notifier.

### Per-tab state should be on the tab, not on AppState

`WorkspaceTab` (`lib/state/workspace_tab.dart`) is a passive struct.
`AppState` reaches into `tab.filter`, `tab.edits`, `tab.columnWidths`,
`tab.applying`, `tab.loading`, `tab.autoRefreshInterval`, etc. directly. The
sealed class is doing very little — it's just a tagged union with mutable
fields.

I'd promote each tab to its own `ChangeNotifier`:

```dart
sealed class WorkspaceTab extends ChangeNotifier {
  // …
}

class TableTab extends WorkspaceTab {
  // owns its own Timer, its own load(), its own setFilter()
  Future<void> reload(PostgresService service) async { … }
}
```

That removes from `AppState`:
- `loadTablePage`, `refreshTable`, `setTableFilter/Order/Select`,
  `cycleTableOrder`, `setColumnSort`, `appendTableFilter`,
  `setTableAutoRefresh`, `_autoRefreshTimers`, `setCellEdit`,
  `revertCellEdit`, `resetTableEdits`, `applyTableEdits` (lines 865–1075,
  roughly 220 lines).

The grid binds to a `Provider<TableTab>` (already mounted under `IndexedStack`)
and only that tab rebuilds when its own data changes. Today, the comment at
`workspace_tab.dart:100-103` ("The Timer itself lives in [AppState] so the
model stays free of dart:async") is actively papering over this — the model
*is* per-tab state; making it depend on `dart:async` is fine.

This also fixes a subtle bug: `_pendingWidths`
(`app_state.dart:802, 810-828`) is keyed by `table.qualifiedKey` but not
guarded against the active connection changing during the 500ms debounce
window. If the user disconnects and reconnects between the resize and the
flush, widths from connection A get written into connection B.

---

## 2. Driver leakage into `models` and `ui`

The architectural rule should be: **only `lib/services/` and `lib/state/` know
about `package:postgres`.** Today:

- `lib/models/value_format.dart:4,18,26` references `UndecodedBytes` directly.
- `lib/ui/cell_picker/cell_picker.dart:5,221,238` imports `package:postgres`
  to dispatch on `UndecodedBytes`.
- `lib/services/postgres_service.dart:130,340` raises `ServerException`
  branches but already catches them — fine. The damage is in models/ui.

Fix: introduce a thin DTO at the service boundary:

```dart
// lib/models/cell_value.dart  — driver-free
sealed class CellValue {
  const CellValue();
}
class TextCell(String value) extends CellValue;
class JsonCell(Object? json) extends CellValue;
class BytesCell(Uint8List bytes, bool isLikelyText) extends CellValue;
class NumberCell(num value) extends CellValue;
// …
```

Then `PostgresService.fetchTablePage` returns `QueryResult<CellValue>` and
`value_format.dart` becomes a pure `CellValue → String` renderer with no
external imports. The cell picker's `_kindFromValue`
(`cell_picker.dart:220`) dispatches on the sealed `CellValue` subclass
instead of the driver's runtime type.

Bonus: today `dataType: row[2] as String` (raw `format_type` output) is
the only type signal flowing past introspection. A small `PgType` enum
(numeric / text / boolean / temporal / json / array / unknown) computed once
in `Introspector` would prevent the brittle string-matching the picker is
about to grow when we add more inputs.

---

## 3. Dependency direction

```
lib/services/postgres_service.dart:6
  import '../state/workspace_tab.dart';   // ← upward
```

This is the only upward dep, and it exists only to take `CellEditValue` in
`applyTableEdits` (lines 352–366) and `buildEditStatements` (line 372). Move
`CellEditValue` / `CellLiteral` / `CellDefault` to `lib/models/cell_edit.dart`
— they're DTOs, not tab state. The class `CellEdit` (row/col coords,
`workspace_tab.dart:47-59`) stays on the tab; the *value* (literal vs
DEFAULT) is a model.

Other directions:
- `lib/models/*` — only `value_format.dart` reaches outside the layer (to
  `package:postgres`). Fix per §2.
- `lib/services/*` — all imports point at `lib/models/*` and `package:*` —
  good once the one upward import is removed.
- `lib/state/*` imports `services` + `models` — correct.
- `lib/ui/*` imports `state` + `models` + `services` (for `ExportFormat`) +
  `package:postgres` — fix per §2 to remove the last item.

Cycles: none detected.

### Repository pattern?

`PostgresService` is doing two distinct jobs: connection lifecycle
(`connect`, `close`, `runQuery`) and table operations (`countRows`,
`fetchTablePage`, `fetchAllTableRows`, `applyTableEdits`, `loadTableDdl`).
Worth splitting:

```
services/
  postgres_connection.dart   // open/close/runQuery + raw execute
  table_repository.dart      // countRows / fetchPage / applyEdits / loadDdl
  introspector.dart          // unchanged
```

This isn't pure-pattern theatre: it lets you mock `TableRepository` in tests
without faking the wire protocol, and `loadTableDdl` (lines 172–299) — which
is mostly string-building — stops sharing a file with `runQuery`. The
`fetchTablePage` `'SELECT t.ctid::text AS __ctid, … LIMIT $limit OFFSET $offset'`
on line 95 also has a SQL-injection-style hazard if `limit`/`offset` ever come
from somewhere other than `tab.pageSize` / `tab.offset` — bind them
parameterised in the repository.

---

## 4. Persistence safety

### Atomic writes — currently absent

Both `lib/services/connection_store.dart:38-41` and
`lib/services/preferences_store.dart:34-36` do:

```dart
await file.writeAsString(jsonEncode(...));
```

A crash, power loss, or even an out-of-disk between truncate and final flush
leaves a zero-byte or truncated JSON file. The `load()` catches and returns
`[]` (`connection_store.dart:31-33`), so the failure mode is **silent total
loss of every saved connection, query, favourite, recent, and column-width
preference.** For a single-user power tool this is the worst persistence
failure mode possible.

Fix: write to `connections.json.tmp`, fsync, then rename:

```dart
Future<void> save(List<ConnectionConfig> connections) async {
  final file = await _file();
  final tmp = File('${file.path}.tmp');
  final raf = await tmp.open(mode: FileMode.write);
  try {
    await raf.writeString(jsonEncode([for (final c in connections) c.toJson()]));
    await raf.flush();
  } finally {
    await raf.close();
  }
  await tmp.rename(file.path);
}
```

(POSIX `rename(2)` is atomic on the same filesystem; APFS honours this.)

### Write amplification

Every favourite toggle, every recent-table addition, every saved-query
keystroke (debounced upstream), every column-width drag tick (debounced),
every connection update calls `_persist()` which serialises and rewrites the
**entire** connections list — not the affected connection. With even 5
connections holding 20 saved queries each, that's a ~50KB JSON re-encode on
every keystroke. Not catastrophic, but on a slow disk it shows up as a
mid-keystroke stutter.

Two cheap remediations:
1. Per-connection JSON files (`connections/{id}.json`) so only the dirty one
   rewrites.
2. Single debounced "dirty + flush in 500ms" inside the store, so all the
   site-specific debouncing in `app_state.dart` (`_widthSaveTimer` etc.) can
   collapse to one centralised one.

### Plaintext passwords (out of scope but worth flagging)

`connection_config.dart:30` + `connection_store.dart` write passwords to
disk in clear text. CLAUDE.md says "personal use only — passwords are stored
in plain text, behind the macOS app-sandbox container." Fine for the user's
threat model; macOS Keychain access via `flutter_secure_storage` would cost
~30 LOC and survive a sandbox container theft, so worth knowing about.

---

## 5. Navigation history

### What's captured

`_NavSnapshot` (`app_state.dart:1098-1129`) captures `(tabId, filter,
selectList, orderBy)`. It does **not** capture:

- `tab.page` — back/forward across pagination is lost. Today filter changes
  reset to page 0 (good), but pure ⌘[ won't restore the page you were on
  inside a filtered view.
- `tab.edits` — uncommitted edits are not part of history; if a user edits a
  cell, navigates away, comes back, edits are still there (because they live
  on the tab). This is probably correct, but it should be a documented design
  choice in the snapshot, not an accident of who owns what.
- Pinned columns / column-set hiding once that lands.
- `_sidebarSearch` / `_expandedSchemas` — schema-tree state is sticky across
  back/forward, which is fine but worth deciding explicitly.

### Race conditions and edge cases

1. **`historyBack` / `historyForward` while a previous `loadTablePage` is
   in-flight** (`_applySnapshot` → `unawaited(loadTablePage(...))` at line
   330): two loads can race. The later-arriving fetch wins regardless of
   which navigation was actually most recent. Pattern fix: each snapshot
   apply should bump a per-tab generation and the loader should compare on
   completion.
2. **Dead-tab IDs in history.** `closeTab` (line 647) and friends remove the
   tab but leave snapshot entries pointing at the dead id. `historyBack`'s
   `while` loop (line 302) gracefully skips them, but the history can fill
   with dead entries and the user has to press ⌘[ many times to traverse
   them. Cheap fix: prune snapshots whose `tabId` is gone, in `closeTab`.
3. **`closeAllTabs` / `closeOtherTabs` / `closeTabsToRight`** don't touch
   `_navHistory` — see above.
4. **No history push on `closeTab`.** Closing a tab silently moves the
   active index but doesn't push, so ⌘[ doesn't reopen the closed tab.
   Possibly intentional; worth deciding.
5. **`disconnect` / `connect` clear history** (lines 375–376, 417–418) —
   good. But the cleared state happens *between* `notifyListeners` calls and
   any in-flight history navigation from the previous connection silently
   targets the now-empty list. Not currently triggerable from UI, but if
   keyboard shortcuts ever fire during connect, watch for it.
6. **`_navigatingHistory` is a single flag,** not a stack. If `_applySnapshot`
   ever does something that itself triggers an `unawaited` reentrant push
   (e.g. through `_replaceActiveConnection` later notifying a widget that
   pushes), the guard collapses. Today it's safe; document the invariant or
   make it a `_pushSuppressionDepth: int`.

The history component is small enough that pulling it into a
`NavigationHistory` ChangeNotifier (per §1) and making it own snapshot
pruning + generation comparison is a one-afternoon refactor.

---

## 6. Cache layers (catalog, columns, FKs)

The catalog model (`lib/models/db_catalog.dart`) is well-shaped — immutable
snapshot, OID-keyed, `CatalogPhase` enum for partial population. The old
`_columnCache` / `_fkCache` per-table caches from the CLAUDE.md description
are gone (the comment at `app_state.dart:107-110` still says so); everything
lives in `DatabaseCatalog`. Good.

What's missing:

- **No partial invalidation.** `refreshCatalog` (line 425) rebuilds the
  whole thing. If a user runs `ALTER TABLE foo ADD COLUMN`, they have to
  refresh the entire catalog (or close/reopen the connection). Fine MVP-wise;
  for production, after a successful DDL `runQuery`, the affected table's
  columns/FKs/indexes should be re-introspected lazily.
- **No memory bound.** Holding 50k columns across 5 large databases (the
  user's case is small but JetBrains-style users open everything) means
  `DatabaseCatalog.columnsByOid` is permanently ~5MB. Fine. But
  `aggregatedSingleColumnForeignKeys` (`db_catalog.dart:107-117`) is rebuilt
  on every getter call — `app_state.dart:144` exposes it as a property,
  callers from `ui/workspace/results_grid.dart` will re-walk every FK on
  every grid rebuild. Memoise it once per `DatabaseCatalog` instance (the
  catalog is immutable, so cache it at construction).
- **`findUniquePrimaryKeyOwner`** (`db_catalog.dart:79-91`) is O(relations ×
  columns) and runs on every cell context-menu open. Same fix — precompute a
  `Map<String, DbTable?>` once per catalog.

---

## 7. Threading

The user lives on the UI isolate. Quick scan turned up no `compute()` or
`Isolate.run` calls. The two operations that can stall the UI:

1. **JSON encode of the connections file** (`connection_store.dart:39-41`).
   With saved queries, 5 connections × 20 queries × 5KB each = ~500KB encode.
   `jsonEncode` is synchronous; on first commit of a long query this will
   stutter a frame. Move the encode into `compute()`.
2. **`PostgresService.fetchAllTableRows`** (line 142) — exports load the
   whole result into memory and the exporter renders the whole CSV/Markdown
   into a `StringBuffer` synchronously (`exporter.dart:42, 87`). For a 1M-row
   export the renderer blocks the UI for seconds. For a personal tool fine
   for now, but `compute(format.render, result)` is a one-line fix.
3. **Catalog phase 1 introspection** (line 462) is already async-on-DB but
   the result decoding into `Map<int, List<DbColumn>>` happens on the UI
   isolate. With 10k columns this is ~50ms. `Isolate.run` for the merge
   would smooth over the post-connect "click is sluggish for half a
   second" moment.

The phase-0 / phase-1 generation guard (`_catalogGeneration` at
`app_state.dart:118`) is correct — `if (gen != _catalogGeneration) return;`
fires after every `await` boundary.

---

## 8. Smaller findings

- `app_state.dart:198` — `lastWhere` with a predicate that may not match
  (the just-opened tab could be at any index if naming collisions with an
  existing tab id ever happen). Today `openTable` either focuses an existing
  tab or appends a new one, so `lastWhere` matches the last appended; if
  tab-reordering is ever added, this breaks silently.
- `app_state.dart:182-188` — `_missingCol` sentinel + `identical(match, ...)`
  is a workaround for `firstWhere`'s no-orElse-default. `firstWhereOrNull`
  from `package:collection` (already in any Flutter project's transitive
  deps) is clearer.
- `app_state.dart:264` — `_idCounter` is monotonic but resets per-`AppState`
  instance, so persisted `SavedQuery.id`s reuse small integers across
  restarts. If the persistence format ever needs to merge across machines or
  versions, that's a collision waiting. Use a `Uuid` or `DateTime.now()
  .microsecondsSinceEpoch.toRadixString(36)`.
- `app_state.dart:225-227` — `_recents` cap is hardcoded to 12; should be
  a named constant somewhere on `WorkspaceUiState`.
- `connection_store.dart:42-44` — silent swallow on save failure. At minimum
  log to `debugPrint` so a developer notices when their disk is full.

---

## Suggested refactor order (incremental, each independently shippable)

1. **Atomic write** in `ConnectionStore` and `PreferencesStore`. ~20 LOC,
   immediate durability win.
2. **Move `CellEditValue` to models, kill the upward import.** ~10 LOC.
3. **Driver-free `CellValue` DTO at the service boundary.** ~150 LOC.
   Unblocks unit tests of the cell picker.
4. **Promote tabs to `ChangeNotifier`s; remove 200 lines from `AppState`.**
   Largest win, but mechanical.
5. **Extract `CatalogController` + `NavigationHistory` from `AppState`.**
6. **Repository split** (`PostgresConnection` + `TableRepository`).
7. **Per-connection JSON files** + centralised dirty-flush in stores.

Each step keeps `flutter analyze → test → build` green; none requires the
next to land before being useful.
