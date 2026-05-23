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

Flutter binaries are at `~/flutter/flutter/bin`. Prefix every command:

```bash
export PATH="/Users/jwo1f/flutter/flutter/bin:$PATH" && flutter <cmd>
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
| State | `provider` + `ChangeNotifier`. Controllers are first-class providers. |
| Postgres | `postgres: ^3.5.0` (extended query mode) |
| SQLite | `sqlite3: ^2.4.0` + `sqlite3_flutter_libs` |
| SQL grammar | `highlight` / `flutter_highlight` (read-only); custom `CodeEditor` (editable) |
| Window chrome | `macos_window_utils` |
| Persistence | `path_provider` → JSON under Application Support |
| File save | `file_selector` |
| Crypto | `pointycastle` (master-passphrase only) |

**Sandbox is OFF** — the app must reopen arbitrary SQLite paths after
relaunch. Entitlements: `macos/Runner/{Debug,Release}.entitlements`.

`MainFlutterWindow.swift` registers a `dbv/window` method channel for
`startDrag` (toolbar pan) and `toggleZoom` (double-click).

## Architecture map

### State layer (`lib/state/`)

`AppState` is a thin orchestrator (~280 lines). It owns ten focused
`ChangeNotifier` controllers and coordinates only cross-controller work:

```
AppState  (orchestration: connect, disconnect, reconnect, refreshCatalog,
          updateConnection, clearQueryMessages, historyBack/Forward,
          findRowInTable, followForeignKey, passphrase coordination)
  ├── PreferencesController
  ├── MasterPassphrase
  ├── ConnectionRegistry
  ├── EventLog
  ├── SessionController
  ├── CatalogController
  ├── NavigationHistory
  ├── WorkspaceUi
  ├── PerConnectionStore
  └── TabsController
```

`lib/main.dart` provides every controller individually via
`MultiProvider` (`.value` providers; `AppState` owns disposal).
**Widgets watch the specific controller they depend on, NOT `AppState`.**
A widget that needs methods from two controllers reads both — don't
capture an `AppState` reference for convenience.

`context.read<AppState>()` is only for invoking orchestration methods
(`appState.connect(...)`, `appState.findRowInTable(...)`). It's NOT
for reading data — read the owning controller directly.

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

### Catalog loading

All three flows (`connect` / `reconnect` / `refreshCatalog`) go through
`CatalogController.load(service, {required awaitPhase1})` plus
`AppState._loadCatalog(awaitPhase1: ...)` for the cross-controller
`WorkspaceUi.expandSingleSchema` piece. Phase-0 errors set
`CatalogController._lastError` the same way phase-1 does — they're
surfaced in the sidebar's schemas section.

### Persistence

All writes to `connections.json` go through
`ConnectionStore.saveDebounced(...)` (100 ms debounce). The store sits
on `AtomicJsonFile`, which serializes overlapping writes via an
internal chain and exposes `drain()` for shutdown.

`AppState.flush()` → `ConnectionRegistry.flush()` →
`ConnectionStore.flush()` is wired into
`AppLifecycleListener.onExitRequested` in `main.dart`. Pending writes
are durable on quit.

**Never use `unawaited(_store.save(...))`** or any direct file write —
the debounced funnel is the only path.

### Service layer (`lib/services/`)

Shared cross-engine helpers — do not duplicate:

| Module | Surface |
|---|---|
| `sql_render.dart` | `whereClause`, `orderClause`, `literalSql`, `renderAssignment`, `validateClauseSnippet`, `ClauseSyntaxException`, `ClauseKind` |
| `db_service.dart` | `versionTag`, `timedEdit` |
| `driver_decoder.dart` | `decodeDriverRow` |
| `sql_statements.dart` | `parseSqlStatements` |

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
| Sidebar | `lib/ui/sidebar/` — 12 files; composition root in `sidebar.dart` |
| Query plan view | `lib/ui/workspace/query_plan/` — layered: `model/`, `parsing/`, `analysis/`, `glossary/`, `view/` |
| Results grid | `lib/ui/workspace/results_grid/` — 14 files |
| Code editor | `lib/ui/widgets/code_editor/` — layered: `controller`, `indent` (pure), `metrics`, `suggestions/`, `view` |

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

### Code editor

The indent functions (`handleTab`, `shiftLines`, `handleNewlineInsert`,
`tokenStart`) are PURE — they take
`({String text, TextSelection selection, ...})` and return an
`EditResult` record. No widget refs. Tested in
`test/ui/widgets/code_editor/indent_test.dart`.

Newline boundary inclusion follows modern editor convention: a
selection ending exactly at the start of line N+1 does NOT extend the
shift into N+1.

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

Clause changes go through the atomic
`TabsController.loadTablePage(tab, page, clauses: ...)`: clauses swap
together with new rows on success. A failing fetch leaves prior
clauses + prior rows visible — the view never desyncs from the data.

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
- **Do not** mutate a `CodeEditorController` from inside a `build`
  method — schedule via `didUpdateWidget` or a listener.
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

## Memory pointers

User memories under
`~/.claude/projects/-Users-jwo1f-work-jwo1f-dbv-dbv/memory/` — font
preferences, theme aesthetic, commit style, UI-redesign discipline.
Read these on a fresh session.
