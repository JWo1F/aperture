# dbv

A macOS PostgreSQL viewer for power users — a personal, opinionated
client built in Flutter.

Built for one person. Dense, keyboard-driven, deliberate; not a
consumer product. Source open for anyone who wants to fork it and run
their own.

## What it does

**Browse**
- Translucent sidebar with saved connections, recently-used tables,
  favourites, and the live schema tree.
- Schema search (⌘F) filters the table list as you type.
- ⌘K command palette jumps to any table, switches connections, runs
  named actions.

**Query data**
- Editable data grid with lazy `ListView.builder` rendering, resizable
  columns (per-table widths persisted), type-aware cell colours, inline
  JSON syntax highlighting, hover-to-reveal full values.
- Single-row clausebar with `SELECT` · `WHERE` · `ORDER BY` inputs —
  applied on `↵`, with SQL syntax highlighting and column-header
  click-to-sort with multi-column priority.
- Right-click any cell for: copy / copy as JSON / Set NULL / Set DEFAULT
  / revert / filter by value / sort / follow foreign key / find row in
  related table.
- Foreign-key columns marked with a ↗ indicator; click → opens the
  referenced table filtered to the matching row.
- Tab navigation history (⌘[ / ⌘]) — back/forward through every tab
  switch *and* filter / sort change.

**Edit cells**
- Double-click any cell for a type-aware overlay picker anchored to the
  cell:
  - text / json (with live JSON highlight)
  - bool toggle
  - integer / numeric (digit-only input filters)
  - date (refined Material 3 calendar with Aperture palette)
  - time / timetz (HH : MM : SS . ms segments + optional timezone row)
  - timestamp / timestamptz (calendar + time + tz)
- Set NULL / Set DEFAULT / Today / Now in the picker footer; disabled
  when the schema forbids them.
- Edits stage in memory with a per-cell highlight; **Apply** sends every
  pending change as one `UPDATE` transaction keyed by `ctid`.
- Pending-edits modal (click the badge) previews every `UPDATE` with
  full SQL highlighting before commit.

**Run SQL**
- Multi-line code editor with `pgsql` grammar, autocomplete fed by the
  loaded schema (tables + columns), gutter line numbers + a per-
  statement ▶ icon to run blocks individually.
- Statements are parsed (single/double-quoted strings, line comments,
  block comments handled correctly). `⌘↵` runs everything; `⌘⇧↵` runs
  the statement under the caret.
- Multi-statement scripts are split client-side and executed in
  sequence — the postgres extended-query protocol's "cannot insert
  multiple commands" error is handled invisibly.
- Per-query autosave (400 ms debounce) to the active connection's
  saved-query list; queries appear in the sidebar and survive restarts.
- Right-click saved queries for: open / rename / duplicate / copy SQL /
  delete.

**Explore schema**
- `CREATE TABLE` viewer per table: full DDL reconstructed from
  `pg_catalog` — columns with `format_type()` output, PK / FK / UNIQUE /
  CHECK constraints via `pg_get_constraintdef`, indexes from
  `pg_indexes`, column + table comments — selectable and copyable, with
  proper line numbers.

**Export**
- CSV export from any table view (current page or all filtered rows) or
  query result via the native macOS save dialog. The exporter is
  designed to accept additional formats (JSON, XLSX, …) by adding a
  single subclass to `lib/services/exporter.dart`.

**macOS-native window**
- Transparent titlebar with full-size content view; traffic lights
  overlay our toolbar; pan-to-move and double-click-to-zoom wired via a
  Swift method channel.
- Custom **command palette** (⌘K), **back/forward** (⌘[ / ⌘]),
  **search** (⌘F) keyboard shortcuts.

## Aesthetic

"Aperture" theme — near-black panels, a single indigo accent
(`#5B7CFA`), hairline borders, Inter for UI text and JetBrains Mono for
data / SQL / identifiers. The toolbars use a synth-panel rhythm of
labelled segments separated by 1 px vertical rails.

## Tech stack

- **[Flutter](https://flutter.dev/)** for the cross-platform UI (only
  macOS is wired up today).
- **[`postgres`](https://pub.dev/packages/postgres)** as the wire-
  protocol client.
- **[`flutter_code_editor`](https://pub.dev/packages/flutter_code_editor)**
  + **[`flutter_highlight`](https://pub.dev/packages/flutter_highlight)**
  + the **[`highlight`](https://pub.dev/packages/highlight)** package's
  `pgsql` grammar for both editable and read-only SQL views.
- **[`macos_window_utils`](https://pub.dev/packages/macos_window_utils)**
  for the custom titlebar.
- **[`file_selector`](https://pub.dev/packages/file_selector)** for the
  native export dialog.
- **[`provider`](https://pub.dev/packages/provider)** for the single
  root `ChangeNotifier`.
- **[`path_provider`](https://pub.dev/packages/path_provider)** —
  connections + saved queries persisted as JSON in the macOS app-sandbox
  container.

## Running locally

Requires Flutter (channel `stable`, 3.x).

```bash
flutter pub get
flutter run -d macos
```

To build a release `.app`:

```bash
flutter build macos --release
```

Connection details (host / port / database / user / password) are
stored in `~/Library/Containers/com.example.dbv/Data/Library/Application
Support/com.example.dbv/connections.json` — per-user, sandboxed,
plaintext (this is a personal tool, not multi-user software).

## Project conventions

- Built with the help of the
  [CLAUDE.md](CLAUDE.md) guide and the playbooks under
  [.claude/skills/](.claude/skills/).
- Aesthetic + commit style preferences live in user-level memory
  files; the CLAUDE.md links them.
- Power-user density over consumer polish. Three similar lines beat a
  premature abstraction.

## License

Personal project — no license. If you want to fork it, go ahead, but
nothing here is a finished product.
