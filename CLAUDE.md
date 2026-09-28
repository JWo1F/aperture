# Aperture — Claude project guide

Personal macOS Flutter desktop app: a power-user database viewer
for PostgreSQL and SQLite. Built for **one user** (jwo1f). Prefer
density and correctness over consumer polish. Skip backward-compat
shims; if you need to change a contract, change every caller.

## Hard rules

- **Do NOT launch, open, run, or quit the app.** Your loop ends at
  `flutter build`. The user runs and inspects.
- **Do NOT push, force-push, amend a pushed commit**, or anything else
  hard-to-reverse without explicit user request.
- **Do NOT commit unless the user asks** (or you're a subagent whose
  remit explicitly includes committing).
- **No AI / Claude attribution in commits.** No `Co-Authored-By`.
- **No `--no-verify`, no skipped hooks, no bypassed signing** — ever.
- **`flutter analyze` must be clean before committing.** Info-level
  lints are blockers, not suggestions.
- **Both light and dark themes are first-class.** Every color goes
  through `AppColors`. Never hardcode `Color(0x…)` / `Colors.white` /
  `Colors.black` (with the two narrow exceptions in §Theming).
- **No comment temporal framing** (`for now`, `until X lands`,
  `currently`), no **caller references** (`Drives the X partial`,
  `Used by Y`), no **task / PR context** (`added for the Z flow`), no
  **what-the-code-does narration**. Architectural / invariant /
  non-obvious-why comments are welcome.

## Build / test / verify loop

Flutter binaries are at `~/flutter/bin`. Prefix every command:

```bash
export PATH="/Users/jwo1f/flutter/bin:$PATH" && flutter <cmd>
```

After every meaningful change, in this order:

```bash
flutter analyze         # MUST show "No issues found!"
flutter test            # MUST be all green
flutter build macos --debug
```

`build` catches Swift / entitlements / linking issues the analyzer
doesn't. Skip it only for one-line lint-only fixes that touch no Dart
logic.

## Commit discipline

Commit after every completed, verified feature — don't wait to be asked
once a feature is done. One commit per feature; combine tightly related
fixes only when they form one coherent change.

For every commit, in this order:

1. Bump `version:` in `pubspec.yaml` — raise the build number after
   `+`. Bump the version-name per change size: patch for small fixes,
   minor for architectural refactors.
2. Sync `_version` in `lib/ui/about/about_dialog.dart`.
3. Stage **only** the files this change touches. Never `git add -A` /
   `git add .` — the working tree often has unrelated in-progress
   edits AND untracked dirs (`android/`, `macos/Runner.xcodeproj/.../swiftpm/`)
   that must be left alone.
4. Imperative subject under ~70 chars. Body explains **why** (the bug,
   the duplication, the perf problem) — not the mechanics; those are
   in the diff.

**Race avoidance:** do NOT call `Edit` on `pubspec.yaml` in parallel
with a Bash `git add pubspec.yaml && git commit`. The pubspec is
touched externally (linter, user) and a parallel Edit can be silently
dropped. Edit first, then run the Bash sequentially.

**Amending:** prefer NEW commits over `--amend`. The one exception:
you just made an unpushed commit and immediately realize you missed
staging something obviously part of that same logical change (e.g. the
pubspec bump for that commit). Then `--amend --no-edit` is acceptable.

## Stack / dependencies

| Concern | Choice |
|---|---|
| State | `ChangeNotifier` + a process-global `appState`. No `provider`. |
| Postgres | `postgres: ^3.5.0` (extended query mode) |
| SQLite | `sqlite3: ^3.6.0`, built as SQLite3MultipleCiphers (`hooks: user_defines: sqlite3: source: sqlite3mc`) |
| SQL grammar | `highlight` / `flutter_highlight` (read-only views, `CodeField`); `re_highlight` inside `re_editor` |
| Code editing | `re_editor` for multi-line (query editor, cell picker); own `CodeField` for the single-line clause bars |
| Window chrome | `macos_window_utils` |
| Fonts | Inter + JetBrains Mono bundled under `assets/fonts/` (`AppTheme.uiFamily` / `monoFamily`); never fetched at runtime |
| Persistence | encrypted `store.sqlite` under Application Support (`path_provider`) |
| File save | `file_selector` |
| Secrets | login Keychain via the `aperture/keychain` channel; password commands via the login shell |

**Sandbox is OFF** — the app must reopen arbitrary SQLite paths after
relaunch. Entitlements: `macos/Runner/{Debug,Release}.entitlements`.

`MainFlutterWindow.swift` registers an `aperture/window` method channel for
`startDrag` (toolbar pan), `toggleZoom` (double-click) and the window
frame, and an `aperture/keychain` channel (`read` / `write` / `delete`
generic-password items under service `com.jwo1f.aperture`). Ad-hoc-signed
debug builds change signature every build, so macOS asks once per build
before handing the Keychain item over.

## Architecture map

### State layer (`lib/state/`)

`AppState` is a thin orchestrator (~310 lines) and is deliberately **not**
a `ChangeNotifier` — it has no observable state of its own. It owns the
focused notifiers below and coordinates only cross-controller work:

```
AppState  (orchestration: connect, disconnect, reconnect, refreshCatalog,
          updateConnection, clearQueryMessages, historyBack/Forward,
          findRowInTable, followForeignKey, store unlock / Keychain /
          passphrase change, reportUncaught)
  ├── AppStore          (everything persisted: preferences, connections
  │                      and their per-connection bags)
  ├── EventLog
  ├── SessionController
  ├── CatalogController
  ├── NavigationHistory
  ├── WorkspaceUi
  ├── ToastController
  └── TabsController
```

There is **no `provider` package**. Every controller lives for the whole
process, so the element tree had no scoping work to do: widgets reach
them through the global `appState` (`lib/state/app_globals.dart`), set
once in `main()` — before the store is unlocked, so `appState.store` may
still be closed (`isOpen == false`) when a widget first reads it.

Rebuild subscription comes from `ListenableBuilder` and `Selector`
(`lib/ui/widgets/value_selector.dart` — ours, not provider's). **Watch
the narrowest slice you can:** `AppStore` fires one notification for
every mutation it holds, so a widget that reads only `sidebarVisible`
must gate on it via `Selector` rather than rebuilding on every column
resize. `Listenable.merge([...])` plus a record-valued selector is the
pattern for a widget that depends on several controllers (see
`AppShell.build`).

Derivations that need two controllers but belong to neither are pure
top-level functions — see `lib/state/connection_views.dart`, which
resolves `AppStore`'s qualified-key bags against the live catalog.

### Per-tab state ownership

Every `WorkspaceTab` subtype owns its mutable state PRIVATELY
(`_edits`, `_inserts`, `_deletedRows`, `_messages`, `_columnWidths`).
Public getters return `Unmodifiable{Map,List,Set}View`. Mutators are
tab methods that internally `notifyListeners()`.

**There is NO `markChanged()`.** If you reach for one, you're about to
mutate a tab from outside — add a mutator method to the tab instead.
`TabsController` orchestrates *which* tab is mutated; it never touches
a tab's collections directly. Auto-refresh timers live on the tab;
`tab.dispose()` cancels them.

**`edits` and `deletedRows` are keyed by row INDEX into `result.rows`,
so `beginPageLoad` drops both.** Anything that replaces the rows
invalidates every index addressing them — a surviving delete index
resolves against the *new* page's `rowIds` on the next Apply and removes
whatever row landed in that slot, and `affectedRows == 1` can't catch it
because that row exists. If you add another row-indexed collection,
clear it there too. Pending `inserts` survive deliberately: they carry
column names and values, and `buildSlots` re-anchors a stale `afterRow`.

Anything that can throw between `beginApply()` and `endApply()` must be
inside the `try/finally` — a leaked `applying` flag makes every later
Apply a silent no-op for the rest of the tab's life.

### Catalog loading

All three flows (`connect` / `reconnect` / `refreshCatalog`) go through
`CatalogController.load(service, {required awaitPhase1})` plus
`AppState._loadCatalog(awaitPhase1: ...)` for the cross-controller
`WorkspaceUi.expandSingleSchema` piece. Phase-0 errors set
`CatalogController._lastError` the same way phase-1 does — they're
surfaced in the sidebar's schemas section.

### Persistence

Everything persisted lives in ONE encrypted SQLite file,
`store.sqlite`, behind `StoreDatabase` (`lib/services/store_database.dart`).
It is keyed with SQLite3MultipleCiphers in SQLCipher-4 mode
(`PRAGMA cipher = 'sqlcipher'; PRAGMA legacy = 4; PRAGMA key = …`), so a
wrong passphrase fails on the first read and any SQLCipher 4 tool opens the
file. The schema is normalized — `connections`, `saved_queries`,
`query_messages`, `favorite_tables`, `recent_tables`, `table_use_counts`,
`column_widths`, `preferences` — versioned by `PRAGMA user_version`.

The store is sealed until unlocked. `main()` tries the passphrase
remembered in the login Keychain before the first frame; otherwise
`ApertureApp` shows `UnlockScreen` (create-passphrase on first run, unlock
after, "Forgot" erases the file) instead of `AppShell` until
`AppStore.isOpen`. There is no recovery: a lost passphrase means erasing.
`AppState` owns unlock, Keychain and passphrase change (`rekey`).

`AppStore` keeps the whole model in memory. Every mutator ends in
`_changed()`, which marks dirty and (re)schedules a single coalesced
500 ms write; the write is a full snapshot replaced in one transaction, so
a crash leaves the old state or the new one. Before `open` writes are
no-ops.

`AppState.flush()` → `AppStore.flush()` is wired into
`AppLifecycleListener.onExitRequested` in `main.dart`, which is also
where the pending-edit quit guard lives (every quit route — ⌘Q, the app
menu, the Dock, logout — converges there, so do NOT re-add a ⌘Q key
handler). Pending writes are durable on quit.

**Never write a persisted field outside an `AppStore` mutator** and
never touch the file directly — `_changed()` is the only path.

A connection's password is a `PasswordCredential` (stored in the sealed
store) or a `CommandCredential` — a shell command run through the login
shell (`$SHELL -l -c`) on every connect whose stdout, minus the final
newline, is the password (`PasswordCommand`).

### Service layer (`lib/services/`)

Shared cross-engine helpers — do not duplicate:

| Module | Surface |
|---|---|
| `sql_render.dart` | `whereClause`, `orderClause`, `literalSql`, `renderAssignment`, `buildEditStatements`, `EditPolicy`, `validateClauseSnippet`, `ClauseSyntaxException`, `ClauseKind` |
| `sql_identifier.dart` | `quoteIdent`, `qualify` — the ONLY way to embed an identifier |
| `db_service.dart` | `versionTag`, `timedEdit` |
| `driver_decoder.dart` | `decodeDriverRow` |
| `sql_statements.dart` | `parseSqlStatements`, `statementAtOffset` |
| `safe_query.dart` | `applyDefaultLimit` — caps bare `SELECT`s at 10k |
| `store_database.dart` | `StoreDatabase` — the encrypted settings file, `StoreSnapshot` |
| `password_command.dart` | `PasswordCommand` — runs a command credential |
| `keychain.dart` | `Keychain` — the remembered store passphrase |

Backend triad: `DbService` / `Introspector` / `TableRepository` — each
implemented by `Postgres*` and `Sqlite*`. The interface is clean;
implementations diverge in legitimately-engine-specific ways (ctid vs
rowid, INSERT-vs-UPDATE `DEFAULT` handling, transaction model). Do not
force shared abstractions where the engines genuinely differ.

**The introspector instance is cached** in a service field, created in
`connect()`, cleared in `close()`. The SQLite per-table PRAGMA cache
lives on the instance — a fresh-instance getter would defeat it.

### Clausebar safety gate

User-supplied `filter` / `orderBy` / `selectList` are free SQL by
design. Before the repository concatenates them, it MUST gate through
`validateClauseSnippet(snippet, kind: ClauseKind.x)`. Multi-statement
input throws `ClauseSyntaxException` with a clean message. This gate
is the single defense against `1=1; DROP TABLE x` style injection
(SQLite's `_db.select` doesn't refuse multi-statement on its own).

### Postgres driver gotchas

1. `name`-typed columns in `pg_catalog` (OID 19) have no codec — cast
   to `text` in DDL queries.
2. `citext` arrives as binary `UndecodedBytes` with valid UTF-8 —
   `formatCellValue` decodes as text when no sub-space control bytes
   are present.
3. Multi-statement scripts can't go through extended-query. Split via
   `parseSqlStatements`, send each through `runQuery(sqlOverride:)`.
4. JSON / JSONB arrive as `Map` / `List`. Don't `toString()` — use
   `jsonEncode(..., toEncodable: ...)`. `formatCellValue` already does.
5. Cell editability uses `ctid`; SQLite uses `rowid`. UPDATEs use
   `WHERE ctid = '(0,5)'::tid`.
6. Postgres `applyEdits` uses the driver's `runTx`. SQLite hand-rolls
   BEGIN/COMMIT/ROLLBACK with a defensive `_safeRollback` (swallows
   rollback errors so the ORIGINAL exception propagates, and recovers
   stuck-tx state via `Database.autocommit`).
7. `CellDefault` on a SQLite UPDATE assignment is filtered OUT of the
   SET list (SQLite rejects `SET col = DEFAULT`). Postgres UPDATE
   accepts `SET col = DEFAULT`; SQLite INSERT accepts `DEFAULT` in
   VALUES. The `renderAssignment` helper stays correct for both; only
   the SQLite UPDATE site filters.

## UI layer

Decomposed modules — keep files small (target ≤ 400 lines, larger
allowed for cohesive presentational widgets like `plan_node_card.dart`):

| Surface | Module |
|---|---|
| Sidebar | `lib/ui/sidebar/` — 11 files; composition root in `sidebar.dart` |
| Query plan view | `lib/ui/workspace/query_plan/` — layered: `model/`, `parsing/`, `analysis/`, `glossary/`, `view/` |
| Object tab | `SchemaTab` over a sealed `SchemaObject`; `schema_view.dart` + `lib/ui/workspace/object_view/` — Info (plain-language, relations only) and DDL |
| Results grid | `lib/ui/workspace/results_grid/` — 20 files |
| SQL editor | `lib/ui/workspace/query/sql_editor.dart` (`re_editor`) + `sql_autocomplete.dart`; shared style/keys in `lib/ui/widgets/code_view.dart` |
| Clause-bar field | `lib/ui/widgets/code_editor/` — `CodeField`, `controller`, `token`, `suggestions/` |

`lib/ui/widgets/code_editor.dart` is a 1-line barrel re-export; existing
imports point through it. The real module is `code_editor/`.

### Shared primitives (use these, don't duplicate)

| Widget / helper | File | What |
|---|---|---|
| `TreeRow` | `sidebar/tree_row.dart` | Hover + active + indent + tap chassis for tree rows |
| `GridCell` | `results_grid/grid_cell.dart` | Cell paint contract (background, edit stripe, focus ring, deleted-opacity, intrinsic-vs-fixed width) |
| `gridRowFill` | `results_grid/cell_style.dart` | Pure row-fill blend |
| `showTextPrompt` | `widgets/text_prompt_dialog.dart` | Reusable single-text-field modal |
| `createConnectionFlow` / `editConnectionFlow` | `connection/connection_flow.dart` | Canonical create/edit dialog flow |
| `withCommas`, `compactCount`, `compactBytes`, `tableStat` | `models/count_format.dart` | Number formatters |
| `showContextMenu` (+ `CmItem`, `CmDivider`) | `widgets/context_menu.dart` | Right-click menus |
| `AppButton`, `IconAction`, `Rail`, `KbdChip`, `EmptyState`, `TableGlyph` | `widgets/` | Standard chrome |

If you're about to write a "mirrors X" or "replicates Y" comment, stop
and extract the shared thing instead.

### Theming

`darkPalette` and `lightPalette` in `lib/theme/app_theme.dart` are the
two sources of truth. `AppColors` swaps at runtime. EVERY color goes
through `AppColors`. Permitted exceptions:

- `Colors.transparent` — theme-agnostic, always fine.
- `Colors.white` on a saturated accent / error / connection-color
  background — reads the same in both themes.

If you need a color the palette doesn't have, add a field to `Palette`
(BOTH dark + light values) and a getter on `AppColors`. Inlining a
`Color(0x…)` literal is a CLAUDE.md violation.

**Never store an `AppColors` value in a top-level or `static final`.**
Those resolve once per process, so the colour pins whichever palette was
active at first paint and never follows a dark ⇄ light swap. Use a
getter (`apertureCodeStyles`, the `_k*` records in `cell_picker/kinds.dart`)
or read `AppColors` at the call site. The exception is
`results_grid/grid_metrics.dart`, whose styles are `final` for their
*metrics* on the hot path — every call site supplies a live colour, and
the baked one must not be read.

The theme toggle re-keys `AppShell` (`ValueKey(brightness)` in
`main.dart`), which remounts the whole tree — that is what makes a
static `AppColors` work at all, and it also resets grid scroll offsets
and editor undo history. Don't rely on widget `State` surviving a theme
switch.

After any UI change, sanity-check BOTH themes — toggle via the toolbar
button or the ⌘K palette ("Switch to light/dark theme").

`apertureCodeStyles` in `lib/theme/code_theme.dart` is the single
source of truth for SQL/JSON highlighting — touch once and every
highlighter updates.

### Cell-editing surfaces

`MonoValueLine`'s `_Seg` is THE editable HH:MM:SS surface for time and
timetz. **Do NOT** create a parallel segment editor in a body widget —
the time/timetz body is just the optional `TzInput`.

`formatCellValue` in `lib/models/value_format.dart` uses
`toIso8601String()` for `DateTime` and `jsonEncode(..., toEncodable: ...)`
for Map/List so nested `DateTime` round-trips correctly through display
↔ edit. The shape must stay aligned with
`lib/ui/cell_picker/editor_state.dart`.

**`formatCellValue` is a DISPLAY formatter — it elides binary at 16
bytes.** Anything that hands the value onward rather than painting it
(file export, clipboard copy) must use `exactCellValue`, or it passes
off the head of a blob as the whole value. `equalityFragment` still has
this bug for binary: a bytea literal is spelled differently by the two
engines and it has no engine context, so "filter by this value" on a
binary column builds a filter that matches nothing.

### Code editing

Multi-line code is `re_editor`, which lays out and paints only the lines
in view. Its caret is a `CodeLinePosition` (line, column); the SQL
tooling speaks flat offsets — convert with `flatOffset` in
`sql_autocomplete.dart`.

`re_editor` publishes the visible lines' positions to its indicator
**from its layout pass**. Anything driven by them — the gutter's run
icons, the statement bands — must repaint, never rebuild: the icons are
a `Flow` placed at paint time, the bands a `CustomPainter`.

Its key map comes from `AppCodeShortcuts` (`code_view.dart`), which drops
⌘↵ / ⇧⌘↵ / Esc so they reach the query editor and the cell picker, and
drops find / replace / save. `re_editor` caches the platform in top-level
finals on first read, so a widget test that needs its desktop behaviour
sets `debugDefaultTargetPlatformOverride = TargetPlatform.macOS` before
the first pump.

The query editor's autocomplete is `re_editor`'s own: it opens only on
typed input (no Ctrl-Space, no reopen after accepting), Enter accepts,
and Esc does not close it. `CodeField` keeps the app's own popup (Tab
accepts, Ctrl-Space, Esc).

### Query plan view

Advice rules are first-class top-level pure functions in
`lib/ui/workspace/query_plan/analysis/advice_rules.dart`. The registry
is `const List<AdviceRule> adviceRules` in `analysis/advice_engine.dart`.
Adding a new rule = write a function + append to the list. Each rule
gets unit tests in `test/ui/workspace/query_plan/advice_engine_test.dart`
(positive + negative case).

## Common patterns

### Bundled deps for many-controller widgets

If a subtree needs many controllers (sidebar, command palette), thread
a typed `*Deps` bundle through subwidgets rather than `context.read`-ing
at every level. See `SidebarDeps`, `_PaletteDeps`. The bundle is
captured once at the root and reused.

### Debounced persistence

For frequent updates (column resize drag, SQL autosave): a `Timer?`
field that's `cancel()`'d on each tick and re-scheduled. The disk-write
debounce lives in `ConnectionStore`; the column-width drag debounce
lives in `PerConnectionStore`.

### High-frequency rebuilds

`setState` is fine for low-frequency updates. For hot paths (column
resize drag, hot scrolling), use a `ChangeNotifier` + `ListenableBuilder`
at the leaf so only the geometry-dependent subtrees rebuild. The
`ResultsGrid`'s `ColumnWidths` is the model — copy that pattern.

### Navigation history

`NavSnapshot` (in `lib/state/navigation_history.dart`) is canonical.
Compare snapshots with `operator==` — do NOT re-derive per-field
change detection.

History playback goes through the atomic
`TabsController.loadTablePage(tab, page, clauses: ...)`: the clause
triple swaps together with the new rows on success, and a failing fetch
leaves the prior clauses + prior rows visible.

The clausebar's own path does NOT use it — `setTableFilter` /
`setTableOrder` / `setTableSelect` mutate the tab eagerly so the bar
echoes what the user typed, which means a failing fetch shows the new
clause above the old rows. Routing those through `clauses:` is the fix
if that desync ever matters; don't assume it's already the case.

### Search pools

If a widget searches across cached collections (command palette pool),
build the pool ONCE in `initState`. Per-keystroke work re-scores; it
doesn't reallocate items.

## What NOT to do

- **Do not** abstract until you have at least three callers. Three
  similar lines beat a premature abstraction.
- **Do not** add fallback branches for impossible cases. Trust
  internal callers; validate at system boundaries.
- **Do not** write doc-comments that restate the method name.
- **Do not** add backwards-compat shims, deprecated wrappers, legacy
  fields, or `// removed` placeholders. One user. Change every caller.
- **Do not** keep dead code alive with `// ignore: unused_element`. Delete.
- **Do not** mutate a tab's collection directly — use the tab's
  mutator method.
- **Do not** mutate a `CodeEditorController` or a
  `CodeLineEditingController` from inside a `build` method — schedule via
  `didUpdateWidget` or a listener.
- **Do not** rebuild `_ResultsGridState` on a column-resize tick —
  subscribe via `ListenableBuilder` on `ColumnWidths`.
- **Do not** drive-by-fix latent bugs during a refactor. Flag in the
  report. Refactors that mix logic changes are hard to review.
- **Do not** force shared abstractions across Postgres / SQLite where
  the engines genuinely differ (transactions, default semantics, row
  identity).
- **Do not** run the app. Your loop ends at `flutter build`.

## Lessons learned (concrete)

- **The user manually bumps versions sometimes.** `pubspec.yaml` may
  be touched externally (linter, user). Don't revert it. If you wrote
  `1.7.0+39` and the file is now `1.8.0+45`, the user knew what they
  were doing — use that as your new baseline.
- **Working tree may be dirty.** Pre-existing in-progress edits AND
  untracked dirs (`android/`, `macos/.../swiftpm/`) are normal. Never
  blanket-stage; never touch them.
- **Re-run `flutter analyze` yourself** after sub-agent work. Agent
  reports of "clean" have been wrong (missed info-level lints in new
  test files).
- **Don't pin a "probably buggy" test.** Either fix the bug or
  confirm the behavior is correct and document the convention. Pinning
  half-measures leaves the codebase in limbo.
- **`sqlite3` package has no `runTx`-style helper.** Hand-roll with
  `_safeRollback` + autocommit recovery.
- **`postgres` package has `runTx`.** Use it.
- **The `connection/connection_dialog.dart` (top-level) is a 4-line
  re-export shim** over `dialog/connection_dialog.dart`. Both are
  legitimate; don't delete the shim thinking it's dead.
- **Parallel Edit + Bash on the same file races.** Especially
  `pubspec.yaml`. Do them sequentially.
- **`flutter analyze` info-level lints block a commit** for this
  project. Treat them as errors.
- **`flutter build macos` needs full Xcode**, not just Command Line
  Tools. Where only CLT is installed, `analyze` + `test` is the whole
  loop available — say so rather than claiming a build passed.
- **The keepalive must never log.** `SessionController` probes every 30s
  via `DbService.ping()`, which deliberately bypasses `QueryLogger`;
  routing it through `runQuery` again would refill the event log's
  500-entry ring buffer with `SELECT 1` in an afternoon.
- **A `ChangeNotifier` here has no disposed-guard.** Several controllers
  `notifyListeners()` after an `await` (`_fetchServerVersion`,
  `_runKeepalivePing` → `markLost`); a future landing after `dispose()`
  throws. Add a guard when you touch one of those paths.
- **`AnimatedContainer` cross-fades color through pure black when one
  end is `Colors.transparent`.** `Color.lerp(transparent, X, t)` walks
  through `Color(00, 00, 00, t·alpha)` — visible as a dark flash on a
  fading-in hover background. Use `<target>.withValues(alpha: 0)` as
  the off state so the lerp stays inside the target hue. `TbIcon` and
  the toolbar pending actions both follow this rule.

## Known gaps

Real, deliberately unfixed. Don't rediscover them as new findings.

- **`KbdChip` has three private near-copies** (`_QtInlineKbd` in
  `query_editor.dart`, `_TbKbd` in `toolbar_widgets.dart`, `_InlineKbd`
  in `pending_edits_modal.dart`). Each needs a slightly different size;
  the shared primitive should take `parts` + a size + an `onAccent` flag.
- **Postgres's unfiltered row count is a `reltuples` estimate** served
  as exact (`PostgresTableRepository.countRows`), and `pageCount` is
  derived from it — a low estimate hides the last pages of real rows.
  Needs an "≈" in the pagebar or an exact count behind it.
- **The clipboard's cell vocabulary is two bare tokens.** `NULL` and
  `DEFAULT` round-trip through `clipboard_cells.dart`, matched exactly
  and case-sensitively, so the literal text `NULL` can't be pasted into
  a text column — use the cell editor. An empty cell stays an empty
  string.
- **SQLite never sets `PRAGMA foreign_keys = ON`**, so `ON DELETE
  CASCADE` doesn't fire on a delete from the grid. Matches the `sqlite3`
  CLI default; a deliberate choice to revisit, not an oversight.
- **Identity is positional for pending mutations.** `edits` and
  `deletedRows` are keyed by row index, so a page load drops them (see
  §Per-tab state ownership). Keying by `rowId` would let them survive
  instead — a product decision, not a bug.
- **`equalityFragment` truncates binary**, so "filter by this value" on a
  bytea / BLOB column builds a filter matching nothing. Fixing it needs a
  bytea literal, which Postgres and SQLite spell differently, and the
  function has no engine context.
- **A reused `ctid` defeats the affected-row guard.** The guard catches a
  row that moved or vanished, not a line pointer that a `VACUUM FULL` /
  `CLUSTER` / `pg_repack` handed to a different row — that UPDATE hits
  exactly one row, the wrong one. Narrow unless the user runs repack
  jobs; the fix is to include the row's old values in the predicate, or
  use the primary key when the catalog has one.
- **The grid builds every column of every visible row.** The horizontal
  scroller is a `SingleChildScrollView`, so columns can't virtualize: an
  80-column catalog table rebuilds ~25 × 80 cells per resize tick. The
  format cache spares the string work, not the text layout. Structural.
- **`snapshotInserts()` is a shallow copy.** Its doc promises the caller
  a non-aliasing list, but the `PendingInsert.values` maps inside it are
  the live ones. Nothing writes through them today, and all the SQL is
  rendered before the first await, so the window is a microtask.
- **Nothing is keyboard-focusable.** Every button is `Hoverable`
  (`MouseRegion` + `GestureDetector`) with no `Focus` or `Semantics`, so
  Tab traversal and VoiceOver reach nothing. Deliberate for a one-user
  tool driven by explicit shortcuts.
- **The sidebar rebuilds on any tab notification.** Keystrokes no longer
  reach it (`QueryTab.sql` doesn't notify), but a cell edit still
  re-derives the favourites and frequent lists and re-allocates a row
  widget per table. Its `ListenableBuilder` wants to be a `Selector`.

## Naming

The project is `aperture` throughout: the Dart package, the bundle
identifier `com.jwo1f.aperture`, the `aperture/window` method channel,
the `aperture.store` / `aperture.window` log names. Nothing should say
`dbv` any more — if you find one, it's a leftover, not a convention.

Two of those are load-bearing and cannot be renamed casually:

- **`PRODUCT_BUNDLE_IDENTIFIER`** keys
  `~/Library/Application Support/<id>`, where `store.sqlite` lives.
  Changing it points the app at an empty directory and orphans the saved
  connections.
- **The cipher pragmas in `StoreDatabase._applyKey`** (`cipher =
  'sqlcipher'`, `legacy = 4`). Changing either makes every existing store
  fail to open, reported as a wrong passphrase, unrecoverably.

## Memory pointers

Font preferences, theme aesthetic, commit style and UI-redesign
discipline are under
`~/.claude/projects/-Users-jwo1f-work-jwo1f-dbv-dbv/memory/` — a path
keyed to where the repo used to live. The project is now at
`~/work/jwo1f/aperture`, whose own memory directory
(`-Users-jwo1f-work-jwo1f-aperture`) is empty, so a session started here
loads none of them. Read the old path explicitly on a fresh session.
