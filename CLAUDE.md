# Aperture — Project guide for Claude

A macOS Flutter desktop app: a personal database viewer for PostgreSQL
and SQLite. Built for **one user** (jwo1f),
so prefer power-user density over consumer polish and skip
backward-compatibility shims when refactoring.

## Build / test loop

The active Ruby version comes from mise; Flutter binaries are in
`~/flutter/flutter/bin`. Standard invocations:

```bash
export PATH="/Users/jwo1f/flutter/flutter/bin:$PATH" && flutter analyze
export PATH="/Users/jwo1f/flutter/flutter/bin:$PATH" && flutter test
export PATH="/Users/jwo1f/flutter/flutter/bin:$PATH" && flutter build macos --debug
```

After every meaningful change run **analyze → test → build** before
committing. Build catches Swift / entitlements issues the analyzer
doesn't.

**Never launch or quit the app yourself.** Don't `open` the `.app`,
`osascript -e 'quit …'`, or `pkill` Aperture — and don't kill an
instance the user already has running. Your loop stops at
`flutter build`; the user runs and relaunches the app and checks the
result.

## Commit style

- **No AI / Claude attribution** in commit messages (no `Co-Authored-By`).
- Imperative subject line under ~70 chars; body explains *why*.
- One feature per commit. Commit after every completed feature without
  being asked.
- **Bump the version before every commit.** Increment `version:` in
  `pubspec.yaml` (raise the build number after `+`, and the version name
  per change size) and keep `_version` in `lib/ui/about/about_dialog.dart`
  in sync. Stage both with the commit.
- See `~/.claude/projects/-Users-jwo1f-work-jwo1f-dbv-dbv/memory/feedback_commits.md`
  and `feedback_commit_discipline.md` for the user's exact preferences.

## Aesthetic

"Aperture" theme — Linear-style restraint with macOS-native polish:

- Near-black `#0E1014` workspace bg, `#13151A` sidebar, `#16181C` surfaces.
- Single indigo accent `#5B7CFA`. No purple gradients, no amber.
- **Inter** for UI text, **JetBrains Mono** for data / SQL / identifiers
  (via `google_fonts`). User has rejected IBM Plex and Material defaults.
- Hairline borders (`AppColors.border`, `borderStrong`). `Rail` widget for
  vertical hairlines between toolbar sections.
- Custom `TableGlyph` (CustomPaint) for table icons instead of Material's
  generic `Icons.table_rows_outlined`.

## Theming — both light and dark are first-class

The app ships **dark and light** variants of the Aperture theme. Both are
shipping surfaces — any UI work MUST look correct in both.

- Every color comes from the active `Palette` via the `AppColors` shim
  (`lib/theme/app_theme.dart`). `darkPalette` and `lightPalette` are the
  two sources of truth; `AppColors` swaps between them at runtime.
- **Never hardcode a `Color(0x…)` or `Colors.white` / `Colors.black` for
  anything theme-dependent** — surfaces, text, borders, tints, shadows,
  scrims. A literal looks fine in whichever theme you tested and breaks in
  the other (e.g. a white-alpha overlay vanishes on a light background; a
  dark-accent ARGB is the wrong hue under the light accent).
- If you need a color the palette doesn't have, **add a field to `Palette`**
  (with both dark + light values) and an `AppColors` getter — don't inline
  it. Shadows use `AppColors.shadow`, modal barriers use `AppColors.scrim`,
  grid row states use `AppColors.gridRow*`.
- `Colors.transparent` is theme-agnostic and fine. `Colors.white` is also
  fine *only* as a foreground on a saturated accent/error/connection-color
  background (white-on-indigo reads the same in both themes).
- After UI changes, sanity-check both themes — toggle via the toolbar
  button or the ⌘K command palette ("Switch to light/dark theme").

User memories under
`~/.claude/projects/-Users-jwo1f-work-jwo1f-dbv-dbv/memory/`:
- `feedback_theme.md` — graphite + indigo direction
- `feedback_fonts.md` — JetBrains Mono / Inter, no IBM Plex
- `project_dbv.md` — personal database tool
- `feedback_commits.md` + `feedback_commit_discipline.md` — commit habits

## Tech stack

| Concern | Choice |
|---|---|
| State | `provider` + `ChangeNotifier` (`AppState`) — single root state |
| Postgres | `postgres: ^3.5.0` driver (extended query mode) |
| SQL grammar | `highlight` + `flutter_highlight` (read-only) + `flutter_code_editor` (editable) |
| Window chrome | `macos_window_utils` — transparent titlebar + full-size content |
| Persistence | `path_provider` → JSON at `Application Support/connections.json` |
| File save | `file_selector` (export) |
| Scroll sync | grid header reads body offset through an `AnimatedBuilder(animation: _hBody)` — `linked_scroll_controller`'s microtask hop felt rubbery on trackpad |

## Architecture

### Single root state — `lib/state/app_state.dart`

`AppState extends ChangeNotifier`. Owns:
- `_connections` list (persisted) + the live `PostgresService`.
- `_tabs: List<WorkspaceTab>` + `_activeTabIndex`.
- `_schemas`, column metadata cache (`_columnCache`), FK cache (`_fkCache`).
- Navigation history (`_navHistory: List<_NavSnapshot>`) — tab switches
  AND filter/select/order changes go through the same stack so ⌘[ / ⌘]
  rolls back uniformly.
- Recent tables (per-connection, persisted).
- Saved queries (per-connection, persisted) with autosave from the editor.
- Column widths per (connection, table), persisted.

### Workspace tabs — `lib/state/workspace_tab.dart`

`sealed class WorkspaceTab`:
- `QueryTab` — SQL editor + result
- `TableTab` — row grid for a relation + filter/order/select state
- `SchemaTab` — read-only DDL viewer

`switch (tab)` on a sealed class is exhaustively checked — when adding a
new tab type, update `Workspace._content` and the tab strip icon in
`workspace.dart`.

### Tabs survive switches

`workspace.dart` uses `IndexedStack` so all tabs stay mounted; switching
preserves scroll, code editor cursor, query results.

## Postgres driver gotchas

The `postgres` package in extended-query mode (default) has a few
surprises we handle:

1. **`name`-typed columns** in `pg_catalog` (OID 19) have no codec — come
   back as `UndecodedBytes`. Always cast to `text` in SQL when querying
   `pg_class.relname`, `pg_attribute.attname`, etc. See
   `postgres_service.dart`'s DDL queries for examples.
2. **`citext` (and other custom text types)** come back as binary
   `UndecodedBytes` with `isBinary: true` even though their bytes are
   valid UTF-8. `formatCellValue` in `models/value_format.dart` decodes
   them as text when no sub-space control bytes are present.
3. **Multi-statement scripts** can't go through extended query — you'll
   get `"cannot insert multiple commands into a prepared statement"`.
   Use `parseSqlStatements` (`services/sql_statements.dart`) to split,
   then send each via `runQuery(sqlOverride: stmt.text)` in sequence.
4. **JSON / JSONB** come back as `Map`/`List`. Don't `toString()` —
   re-encode with `jsonEncode`. `formatCellValue` already does.
5. Cell editability uses `ctid` (`SELECT t.ctid::text AS __ctid, …`)
   for row identity; UPDATEs use `WHERE ctid = '(0,5)'::tid`.

## macOS specifics

- **Not sandboxed.** The app opens SQLite files at arbitrary user paths and
  must reconnect to a saved file connection after relaunch without
  security-scoped bookmarks, so the sandbox is off. Entitlements live in
  `macos/Runner/{DebugProfile,Release}.entitlements`: `DebugProfile` keeps
  `com.apple.security.cs.allow-jit` for the debug Dart VM; `Release` is an
  empty entitlements dict.
- `MainFlutterWindow.swift` registers a `dbv/window` method channel for
  `startDrag` (used by the toolbar's pan handler) and `toggleZoom`
  (double-click handler).
- `app_shell.dart` registers a `HardwareKeyboard.addHandler` for ⌘[ / ⌘]
  (browser-style back/forward through tab + filter history). Other shortcuts
  (⌘K, ⌘↵, ⌘⇧↵) use `CallbackShortcuts`.

## Reusable UI primitives — `lib/ui/widgets/`

| Widget | Purpose |
|---|---|
| `AppButton` | Labeled action button, `primary` / `danger` / `busy` variants |
| `IconAction` | Icon-only button, supports `primary` (accent) + `busy` (inline spinner) |
| `Rail` | Hairline vertical separator for toolbar groups |
| `KbdChip` | Keyboard shortcut hint pill (`⌘↵`, `⌘⇧↵`, …) |
| `EmptyState` | Centered icon + title + message panel |
| `showContextMenu` | Right-click menu primitive — sealed `CmEntry` (`CmItem`, `CmDivider`) |
| `TableGlyph` | Custom 12px table icon (rectangle + header band) |
| `JsonHighlightController` | Live JSON syntax highlighting for editable fields |
| `SqlHighlightController` | Same, for SQL via `highlight`'s pgsql grammar |

## Cell editing system

- **Picker overlay** (`lib/ui/cell_picker/cell_picker.dart`) anchored to
  cell top-left. Shape varies by `_KindId`: text / json / bool / date /
  time / datetime — each has its own size + body widget.
- Type detection uses `DbColumn.dataType` from catalog first, runtime
  value class as fallback. For null cells the catalog type is the only
  signal — `openTable` `await`s `ensureColumns` before showing the grid.
- Edit values are modeled as a sealed `CellEditValue`:
  - `CellLiteral(value)` — null means SQL NULL
  - `CellDefault()` — generates `SET "col" = DEFAULT`
- `_PanelState._resetTick` increments on Today/Now click; passed as
  `ValueKey` to calendar + time inputs to force a fresh rebuild without
  losing the cursor on normal keystrokes.

## SQL highlighting

Three paths share one theme map (`lib/theme/code_theme.dart`):
- `flutter_highlight`'s `HighlightView` for static views
- `flutter_code_editor`'s `CodeField` for the multi-line editor
- `SqlHighlightController` / `JsonHighlightController` for inline /
  overlay text fields

`apertureCodeStyles` is the single source of truth — touch it once and
every highlighter updates.

## Common patterns

### Persistence + hydration

Every persisted item lives on `ConnectionConfig` (per connection):
- `favoriteTables: Set<String>` — schema.table keys
- `savedQueries: List<SavedQuery>`
- `recentTables: List<String>`
- `columnWidths: Map<schema.table, Map<column, width>>`

`_replaceActiveConnection(updated)` mutates the list, updates
`_activeConnection`, calls `_persist()`, and notifies. Use it whenever
you change a `ConnectionConfig` field.

### Debounced persistence

For frequent updates (column resize drag, SQL autosave): use a `Timer?`
field that's `cancel()`'d on each tick and re-scheduled. See
`AppState._widthSaveTimer` and `QueryEditor._saveTimer`.

### Navigation history

`_NavSnapshot` records `(tabId, filter?, selectList?, orderBy?)`. Push
on every meaningful state change (`_selectTab`, `setTableFilter`, etc.).
Apply via `_applySnapshot` which sets `_navigatingHistory = true` so the
mutation doesn't re-push. Dead tab ids are skipped on back/forward.

### Context menus

Right-click anywhere meaningful (cell, table row, query row, tab) opens
a `showContextMenu` overlay. Items are `CmItem` (with optional `icon`,
`shortcut`, `enabled`, `danger`) or `CmDivider`.

For "find row in table" / "follow FK" from query result cells we use
**heuristics** keyed by column name (first match across loaded tables)
rather than resolving `ResultSchemaColumn.tableOid` precisely. Acceptable
trade-off for a personal tool; switch to OID-based resolution if column
name collisions become an issue.

## Things to avoid

- **Don't add abstraction layers** unless they remove duplication that
  already exists. Three similar lines beat a premature trait.
- **Don't write doc comments** that restate the method name. Comments
  should explain *why* / non-obvious invariants.
- **Don't add fallback branches** for impossible cases. Trust internal
  callers; validate at system boundaries (user input, network).
- **Don't reach for AI-generic aesthetics**: Inter as display font,
  purple-on-white, evenly distributed pastel colors. Apply the existing
  palette via `AppColors`.
- **Don't hardcode colors or test only one theme.** Every color goes
  through `AppColors`; verify UI work in both light and dark. See
  "Theming — both light and dark are first-class" above.
- **Don't wait for permission to commit**. Each completed, verified
  feature gets its own commit immediately.

## File map (most-edited surfaces)

```
lib/
  state/
    app_state.dart            — root ChangeNotifier
    workspace_tab.dart        — sealed tab hierarchy
  services/
    postgres_service.dart     — DB client + DDL builder
    sql_statements.dart       — statement parser
    exporter.dart             — extensible export formats (CSV today)
    connection_store.dart     — JSON persistence
  models/
    connection_config.dart    — persisted per-connection config
    db_object.dart            — DbTable / DbColumn / DbForeignKey
    saved_query.dart          — persisted query
    query_result.dart, value_format.dart, order_term.dart, time_ago.dart
  theme/
    app_theme.dart            — palette + typography
    code_theme.dart           — shared SQL/JSON highlight map
  ui/
    app_shell.dart            — Scaffold, toolbar, ⌘K, ⌘[/⌘]
    sidebar/sidebar.dart      — connections + recents + queries + tables
    workspace/
      workspace.dart          — tab strip + IndexedStack
      table_view.dart         — clausebar + grid + pagination
      query_editor.dart       — code editor + run buttons + results
      schema_view.dart        — DDL viewer
      results_grid.dart       — the lazy/typed/clickable data grid
    cell_picker/cell_picker.dart — type-aware overlay picker
    command_palette/command_palette.dart — ⌘K
    connection/connection_menu.dart — toolbar dropdown
    export/export_dialog.dart
    edits/pending_edits_modal.dart
    widgets/                  — common, context_menu, table_glyph, *_controller
macos/
  Runner/MainFlutterWindow.swift  — method channel + window setup
  Runner/{Debug,Release}.entitlements
```
