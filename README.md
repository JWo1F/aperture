# Aperture

A native macOS database client for PostgreSQL and SQLite — dense and
keyboard-driven, built in Flutter.

Power-user density over consumer polish: a translucent schema sidebar,
an editable data grid, a multi-statement SQL editor, and a ⌘K command
palette. Source is open — fork it and run your own.

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
- Edits, row deletes and queued inserts stage in memory with a per-cell
  highlight; **Apply** sends the batch as one transaction, keyed by
  `ctid` on Postgres and `rowid` on SQLite. A statement that doesn't
  affect exactly one row rolls the whole batch back rather than guessing.
- Pending-edits modal (click the badge) previews every statement with
  full SQL highlighting before commit.

**Run SQL**
- Multi-line code editor with `pgsql` grammar, autocomplete fed by the
  loaded schema (tables + columns), gutter line numbers + a per-
  statement ▶ icon to run blocks individually.
- Statements are parsed properly — single and double-quoted strings,
  `E'…'` escape strings, `$$ … $$` and `$tag$ … $tag$` bodies (so
  `CREATE FUNCTION` and `DO` blocks survive), line and block comments.
  `⌘↵` runs everything; `⌘⇧↵` runs the statement under the caret.
- A bare `SELECT` with no `LIMIT` is capped at 10,000 rows, and the grid
  says when it was.
- Multi-statement scripts are split client-side and executed in
  sequence — the postgres extended-query protocol's "cannot insert
  multiple commands" error is handled invisibly.
- Per-query autosave (400 ms debounce) to the active connection's
  saved-query list; queries appear in the sidebar and survive restarts.
- Right-click saved queries for: open / rename / duplicate / copy SQL /
  delete.

**Explore schema**
- `CREATE TABLE` viewer per table — selectable, copyable, line-numbered.
  On Postgres the DDL is reconstructed from `pg_catalog`: columns with
  `format_type()` output, PK / FK / UNIQUE / CHECK constraints via
  `pg_get_constraintdef`, indexes from `pg_indexes`, column + table
  comments. On SQLite it's the verbatim `sqlite_master` text, reflowed
  one column per line, plus standalone index DDL.
- `EXPLAIN` plan view with a node tree and a rule-based advice pass —
  sequential scans, disk sorts, estimate mismatches, batched hashes.

**Keep an eye on things**
- Activity log (⌘L): every statement the app sent, with timing, rows
  affected and errors — a 500-entry ring buffer for the session.
- Floating toasts for anything that fails out of band.
- 30-second keepalive; a dropped socket becomes a reconnect banner that
  keeps your tabs and your place instead of dumping you on the welcome
  panel.
- Optional per-tab auto-refresh, which pauses itself while edits are
  staged.

**Export**
- CSV and Markdown, from any table view (current page or all filtered
  rows) or query result — through the native macOS save dialog, streamed
  to disk with a cancel button, or straight to the clipboard. Adding a
  format is one subclass in `lib/services/exporter.dart`.

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

- **[Flutter](https://flutter.dev/)** for the UI (only macOS is wired
  up; the other platform folders are scaffolding).
- **[`postgres`](https://pub.dev/packages/postgres)** as the wire-
  protocol client, and
  **[`sqlite3`](https://pub.dev/packages/sqlite3)** +
  **[`sqlite3_flutter_libs`](https://pub.dev/packages/sqlite3_flutter_libs)**
  for local database files.
- **[`flutter_highlight`](https://pub.dev/packages/flutter_highlight)**
  + the **[`highlight`](https://pub.dev/packages/highlight)** package's
  grammars for read-only SQL and JSON views. The editable editor is
  ours — `lib/ui/widgets/code_editor/`.
- **[`macos_window_utils`](https://pub.dev/packages/macos_window_utils)**
  for the custom titlebar.
- **[`file_selector`](https://pub.dev/packages/file_selector)** for the
  native open/save dialogs.
- **[`pointycastle`](https://pub.dev/packages/pointycastle)** for the
  master-passphrase key derivation and cipher.
- **[`path_provider`](https://pub.dev/packages/path_provider)** — all
  persisted state in one `store.json` under Application Support.

State is plain `ChangeNotifier`s reached through a process-global
`appState`; there is no `provider` package. The sandbox is deliberately
**off**, so the app can reopen arbitrary SQLite paths after a relaunch.

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

Everything persisted — saved connections, per-connection favourites /
recents / column widths / saved queries, preferences, window frame —
lives in a single `store.json` under `~/Library/Application
Support/com.jwo1f.aperture/`, written temp-then-rename so a crash
mid-write can't shred it.

Passwords are **not** in the Keychain. Each connection picks one of
three credential sources:

- **1Password** — a `op://` secret reference, read through the `op` CLI
  at connect time. Nothing sensitive is persisted.
- **Encrypted** — AES-GCM ciphertext in `store.json`, under a key
  derived from a master passphrase (PBKDF2-HMAC-SHA256). The passphrase
  is never stored; unlock once per session.
- **Plain** — the password in `store.json` as typed. Convenient for a
  throwaway local database; treat the file as a secret if you use it.

## Project conventions

- Built with the help of the
  [CLAUDE.md](CLAUDE.md) guide and the playbooks under
  [.claude/skills/](.claude/skills/).
- Aesthetic + commit style preferences live in user-level memory
  files; the CLAUDE.md links them.
- Power-user density over consumer polish. Three similar lines beat a
  premature abstraction.

## License

No license — all rights reserved. Fork it if you like, but nothing
here ships as a finished product.
