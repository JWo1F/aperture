# dbv — Code Quality Review

Scope: file/method/widget-level quality, Dart idioms, duplication, readability.
**Not** architectural decomposition.

## Headline numbers

- `flutter analyze` → **clean (0 issues)**.
- ~13k LOC of Dart across `lib/`. Largest five files alone are **5.7k LOC** (44%).
- `MouseRegion`+`bool _hover = false` pattern reimplemented **20×** as bespoke
  `StatefulWidget`s.
- `GestureDetector` vs `InkWell`: 44 vs 1 (no Material splash on hover-cells —
  intentional with this aesthetic, mention only).
- `dynamic` cell values flow through ~20 signatures with no narrowing.
- TODO/FIXME density: **0**. Commented-out dead code: **0**. Nice.

---

## File-size hot list

| LOC | File | Verdict |
|----:|------|---------|
| 1500 | `lib/ui/cell_picker/cell_picker.dart` | Oversized — 12 widgets in one file |
| 1129 | `lib/state/app_state.dart` | Borderline; has clear logical sections |
| 1033 | `lib/ui/sidebar/sidebar.dart` | Oversized — 10 widgets, 3 of them repetitive |
| 1031 | `lib/ui/workspace/results_grid.dart` | Acceptable: one cohesive grid; `_buildBody` is heavy though |
| 952  | `lib/ui/app_shell.dart` | Toolbar + welcome + status bar can split cleanly |
| 877  | `lib/ui/workspace/table_view.dart` | Split-button + clause chip pull weight |
| 725  | `lib/ui/workspace/query_editor.dart` | Fine as one file |

The user's "no abstraction unless it removes duplication" rule means file size
alone isn't a defect. What follows is the *evidenced* duplication and quality
gaps inside those files.

---

## Top 10 highest-value cleanups

### 1. The `MouseRegion` + `_hover` boilerplate is reimplemented 20 times

20 separate `StatefulWidget`s each store one `bool _hover` and re-build the
identical `MouseRegion(onEnter: setState true, onExit: setState false,
GestureDetector(onTap: …))` scaffolding. Sites include:

- `sidebar.dart`: `_SavedConnectionRow` (l.444), `_SchemaHeader` (l.620),
  `_TableRow` (l.684), `_SavedQueryRow` (l.845)
- `app_shell.dart`: `_CompactSearch` (l.293), `_ClusterCell` (l.461),
  `_RecentCard` (l.712), `_NewConnectionLink` (l.808)
- `cell_picker.dart`: `_BoolChoice` (l.970)
- `table_view.dart`: `_EditCountBadge` (l.745), `_RefreshSplitButton` (l.363)
- `export_dialog.dart`: `_FormatChip` (l.335), `_DestinationChip` (l.421),
  `_ScopeChoice` (l.490)
- `connection_menu.dart`: `_ConnectionEntry` (l.309), the `_ConnectionMenu`
  trigger (l.18)
- `context_menu.dart`: `_RowState` (l.173)
- `workspace.dart`: `_TabState` (l.187)
- `command_palette.dart`: not stateful but the `onHover` callback pattern
  duplicates the concept

Concrete cleanup: a single `Hoverable` widget in `ui/widgets/common.dart`:

```dart
class Hoverable extends StatefulWidget {
  const Hoverable({super.key, required this.builder, this.onTap, this.cursor});
  final Widget Function(BuildContext, bool hovering) builder;
  final VoidCallback? onTap;
  final MouseCursor? cursor;
  // …
}
```

That collapses 20× `StatefulWidget` declarations to ~30 lines and erases ~600
lines of boilerplate. It's a *direct* duplication removal — fits the
"only when it removes duplication" rule.

---

### 2. `cell_picker.dart` is one file too many widgets (1500 LOC, 12 classes)

The file does five different things: type detection (`_kindFor`), value
extraction (`_initial*`), the panel skeleton (`_PickerOverlay`, `_Panel`),
the bodies (`_TextBody`, `_BoolBody`, `_CalendarBody`, `_TimeBody`,
`_DateTimeBody`, `_TimeInput`, `_TzInput`), and Material-theme overrides
(`_CalendarThemed`).

Suggested split, *purely by file*, not adding abstractions:

```
ui/cell_picker/
  cell_picker.dart            // showCellPicker entry + _Panel orchestration (~350 LOC)
  kinds.dart                  // _Kind + _kindFor + _initial* helpers (~150 LOC)
  bodies/text_body.dart       // _TextBody (~80 LOC)
  bodies/bool_body.dart       // _BoolBody + _BoolChoice (~90 LOC)
  bodies/date_time_bodies.dart  // calendar + time + datetime + _TimeInput + _TzInput (~700 LOC)
  bodies/calendar_themed.dart // _CalendarThemed (~120 LOC)
```

No new classes, no facades — just file boundaries that map to the existing
mental model. `_Panel._save`, `_buildBody`, `_isDirty` are easier to scan at
the top of a 350-line file.

---

### 3. `dynamic` cell values are a typing anti-pattern that propagates

`formatCellValue(dynamic)` is the entry point. From there, `dynamic` flows
through ~20 signatures:

- `ResultsGrid.onAddFilter: void Function(String, dynamic, bool)`
- `onFollowForeignKey: void Function(DbForeignKey, dynamic)`
- `onFindRow: void Function(DbTable, String, dynamic)`
- `_buildCell(int, int, dynamic original)`, `_openCellMenu(…, dynamic original)`
- `_colorFor(dynamic value)`, `_wantsTooltip(dynamic, String)`
- `AppState._equalityFragment(String, dynamic)`,
  `followForeignKey(DbForeignKey, dynamic)`,
  `findRowInTable(DbTable, String, dynamic)`
- `_kindFor(dynamic, String?)`, `_initialText(dynamic, …)`, `_initialBool(…)`,
  `_initialMoment(…)`, `_initialTz(…)` — all in `cell_picker.dart`

The Postgres driver hands back a union of {`null`, `bool`, `int`, `BigInt`,
`num`, `DateTime`, `String`, `Map`, `List`, `UndecodedBytes`}.  Replacing
`dynamic` with `Object?` everywhere is one find-and-replace and gives you the
typing the values actually have (`Object?` is what the driver returns).
`is` checks already drive every consumer (`_colorFor`, `_kindFor`,
`_equalityFragment`), so nothing breaks; the lint quality jumps to "explicit
narrowing required" instead of "anything goes".

`columnDataType: meta?.dataType` is also strictly stronger after the change —
the `as` casts in `app_state.dart:477-481` (`results[0] as Map<int, …>`) are
the only places the analyzer can't help, and `Future.wait` returns a typed
record in modern Dart 3 that would let you drop the casts entirely:

```dart
final (cols, fks, indexes, enums, domains) = await (
  introspector.loadAllColumns(),
  introspector.loadAllForeignKeys(),
  introspector.loadAllIndexes(),
  introspector.loadAllEnums(),
  introspector.loadAllDomains(),
).wait;
```

`app_state.dart:468-481` shrinks and the casts disappear.

---

### 4. Equality-fragment / addFilter is implemented twice

`AppState._equalityFragment` (app_state.dart:847) and
`TableView._addFilter` (table_view.dart:108) are the same function with
slightly different output:

```dart
// app_state.dart:847
String _equalityFragment(String column, dynamic value) {
  if (value == null) return '"$column" IS NULL';
  if (value is num || value is BigInt || value is bool) {
    return '"$column" = $value';
  }
  final text = formatCellValue(value) ?? '';
  final escaped = text.replaceAll("'", "''");
  return '"$column" = \'$escaped\'';
}

// table_view.dart:108 (adds NOT/!= variant)
void _addFilter(AppState state, String column, dynamic value, bool not) {
  final String fragment;
  if (value == null) {
    fragment = '"$column" IS ${not ? 'NOT ' : ''}NULL';
  } else if (value is bool || value is num) {
    fragment = '"$column" ${not ? '!=' : '='} $value';
  } else {
    final text = formatCellValue(value) ?? '';
    final escaped = text.replaceAll("'", "''");
    fragment = '"$column" ${not ? '!=' : '='} \'$escaped\'';
  }
  state.appendTableFilter(tab, fragment);
}
```

Bug surface: `_addFilter` forgot `BigInt` in its numeric branch
(table_view.dart:113). A `bigint` PK value would be rendered as a quoted
string and Postgres would coerce — works today, but the two implementations
are out of sync.

Fix: one helper in `lib/models/sql_predicates.dart` (or top-level in
`value_format.dart` — same file already does the cell→string conversion):

```dart
String equalityFragment(String column, Object? value, {bool not = false}) {
  final eq = not ? '!=' : '=';
  if (value == null) return '"$column" IS ${not ? 'NOT ' : ''}NULL';
  if (value is num || value is BigInt || value is bool) {
    return '"$column" $eq $value';
  }
  final text = formatCellValue(value) ?? '';
  return '"$column" $eq \'${text.replaceAll("'", "''")}\'';
}
```

Both call sites collapse to one line.

---

### 5. Exporter duplicates `_cellText` and `_escape` semantics

`exporter.dart:57` and `exporter.dart:135` are byte-identical:

```dart
String _cellText(dynamic raw) => formatCellValue(raw) ?? '';
```

…in two different classes. Lift it onto the `ExportFormat` base class:

```dart
abstract class ExportFormat {
  …
  @protected
  String cellText(Object? raw) => formatCellValue(raw) ?? '';
}
```

The CSV vs Markdown `_escape` methods diverge correctly (different rules), so
leave those alone. Touching the base class is the single point of contact.

---

### 6. `_listEq` reinvents `listEquals`; `_sameColumns` does the same job

```dart
// app_state.dart:238
bool _listEq(List<String> a, List<String> b) { … }

// results_grid.dart:146
bool _sameColumns(List<String> a, List<String> b) { … }
```

Both are open-coded copies of `package:flutter/foundation.dart`'s
`listEquals`. Delete both, use `listEquals(a, b)` directly (which is exactly
what the docstring on `ChangeNotifier` already exists side-by-side with —
`foundation.dart` is already imported in `app_state.dart`).

---

### 7. Two CSV-timestamp-filename builders, copy-pasted

```dart
// query_editor.dart:172 and table_view.dart:197 — identical
final timestamp = DateTime.now()
    .toIso8601String()
    .replaceAll(':', '-')
    .split('.')
    .first;
```

Move into `lib/models/time_ago.dart` (or rename it to `time_format.dart` —
the file is 17 LOC) as:

```dart
String filenameTimestamp([DateTime? now]) => (now ?? DateTime.now())
    .toIso8601String()
    .replaceAll(':', '-')
    .split('.')
    .first;
```

Two call sites, one source.

---

### 8. `_resetTick` in `cell_picker.dart` is a sentinel masquerading as a counter

```dart
// cell_picker.dart:418
// Bumped whenever Now/Today resets the moment; passed as a Key to the
// time/calendar sub-widgets so they refresh their internal state without
// losing the cursor during normal user typing.
int _resetTick = 0;
…
ValueKey('cal-${widget.resetTick}'),
ValueKey('time-${widget.resetTick}'),
```

The integer carries no information beyond "did the reset event fire". A
`UniqueKey` allocated in `_setToNow` and held as `Key? _resetKey` would name
the intent. `_resetTick++` becomes `_resetKey = UniqueKey()`. Same number of
lines, the name finally reads.

This is also the *only* place the codebase uses an integer-as-trigger
pattern, and the comment at l.415-417 has to explain the mechanism precisely
because the name doesn't. Renaming makes the comment redundant — the
project's comment rules say drop it.

---

### 9. `app_state.dart` swallows errors silently in 3 places

```dart
// l.398
} catch (e) {
  _status = ConnectionStatus.error;
  _connectionError = e.toString();
  _service = null;
}

// l.437 — refreshCatalog
} catch (e) {
  _catalogPhase1Loading = false;
  notifyListeners();
}
// `e` is unused.  No user-facing error path for catalog refresh failures.

// l.491 — _loadCatalogPhase1
} catch (_) {
  // Phase 1 is best-effort: a failure here leaves the catalog in its
  // phase-0 state. The user can retry via the refresh control.
}
```

Phase-1 is intentionally best-effort (good). But `refreshCatalog` (l.437)
silently drops a thrown error — at minimum surface it on the connection
status, or `unawaited(Future.error(e))` it so Flutter's `onError` zones
catch it. As-is, a broken catalog after a server-side schema change leaves
the sidebar empty with no signal.

`connect` (l.398) catches **everything**, including programmer errors
(`StateError`, `RangeError`). Narrow to `on Exception catch` or filter for
`PgException`-class types from the postgres driver.

---

### 10. `findRowInTable` and `followForeignKey` use `lastWhere` to find the tab they just opened

```dart
// app_state.dart:198
Future<void> findRowInTable(DbTable refTable, String refColumn, dynamic value) async {
  await openTable(refTable);
  final tab = _tabs.lastWhere(
    (t) => t is TableTab && t.table.qualifiedName == refTable.qualifiedName,
  ) as TableTab;
  await setTableFilter(tab, _equalityFragment(refColumn, value));
}

// app_state.dart:838 — same pattern in followForeignKey
```

`openTable` already located/created the tab; that lookup is being done twice
and is fragile if `_tabs` is mutated by a parallel callback. `openTable`
should return the `TableTab` it focused:

```dart
Future<TableTab> openTable(DbTable table) async { … return tab; }
```

Both callers collapse to:

```dart
final tab = await openTable(refTable);
await setTableFilter(tab, equalityFragment(refColumn, value));
```

Removes the `as TableTab` cast and the `lastWhere` scan.

---

## Lesser polish (Low / Medium severity)

These don't justify standalone entries but are worth a follow-up sweep.

### `Color(0xAA…)` literals live outside the theme module

10 hard-coded shadow/scrim colors across `app_shell.dart`, `cell_picker.dart`,
`context_menu.dart`, `command_palette.dart`, `connection_menu.dart`,
`connection_dialog.dart`, `export_dialog.dart`, `pending_edits_modal.dart`,
and `results_grid.dart:741` (`const Color(0x1A5B7CFA)` — the selection
overlay tint, a brittle duplicate of the indigo accent at 10% alpha).

Add to `app_theme.dart`:
```dart
class AppShadows {
  static const overlay = Color(0x99000000);
  static const heavy = Color(0xAA000000);
  static const scrim = Color(0x88000000);
  static const palette = Color(0x70000000);
}
extension on Color { /* withValues(alpha:) usages can stay */ }
```

`Color(0x1A5B7CFA)` should become `AppColors.accent.withValues(alpha: 0.1)`
(which the codebase already uses elsewhere) — this one is a true theme leak.

### `cell_picker.dart` `_initialMoment` returns `DateTime.now()` as a hidden fallback

```dart
// l.282
return DateTime.now();
```

A null or unparseable timestamp silently becomes "now". Acceptable for a
calendar default, but the function is also called for **time-only** cells
(`_KindId.time`), where defaulting to today's date is fine. Worth a comment;
without one, the fallback reads like a bug.

### `_buildBody` in `ResultsGrid` (l.613-723) — 110-line method

The body builder has six nested scrollables / focus / mouse / listener
wrappers. Pulling the `Listener + GestureDetector + ListView` block into a
`_buildScrollableBody(result, bodyWidth, bodyCtx)` halves the indent and
makes the hit-testing code (the actual interesting logic) readable.

### `_QueryEditor` `_onControllerChange` has an unused boolean

```dart
// query_editor.dart:87
void _onControllerChange() {
  final text = _controller.text;
  var dirty = false;
  if (widget.tab.sql != text) { … dirty = true; … }
  final nextCursor = _computeCursorStmt();
  if (nextCursor != _cursorStmt) { _cursorStmt = nextCursor; dirty = true; }
  if (dirty) setState(() {});
}
```

The `_cursorStmt` branch always wants `setState`; the `sql` branch's
`setState` is what actually re-renders the gutter ▶ icons. Fine as written,
but the name `dirty` is misleading — it conflates "model changed" with
"widget needs rebuild". Rename to `needsRebuild` or split into two
`setState` calls with explanatory inline.

### `app_state.dart:174` `_missingCol` sentinel is awkward

```dart
final match =
    cols.firstWhere((c) => c.name == columnName, orElse: () => _missingCol);
if (identical(match, _missingCol) || !match.isPrimaryKey) { … }
```

`firstWhereOrNull` from `package:collection` reads naturally:
```dart
final match = cols.firstWhereOrNull((c) => c.name == columnName);
if (match == null || !match.isPrimaryKey) { … }
```

Drops the sentinel + the `identical` check + the static field declaration
(l.181-188).

### `_TableToolbar.build` writes through the controllers during build

```dart
// table_view.dart:235
if (!_selectFocus.hasFocus && _select.text != tab.selectList) {
  _select.text = tab.selectList;
}
```

Mutating a `TextEditingController` inside `build()` is a known footgun
(triggers a notify → rebuild during build in some scenarios). Move into
`didChangeDependencies` or react to the `AppState`'s `notifyListeners` via
a separate listener. Flutter doesn't currently complain because setting
`controller.text` to the same string is a no-op, but the next person who
adds logic in this block will be surprised.

### `_RefreshSplitButton._intervals` repeats the duration string

```dart
// table_view.dart:364
static const List<(Duration, String)> _intervals = [
  (Duration(seconds: 5), '5s'),
  (Duration(seconds: 15), '15s'),
  …
];
String _intervalLabel(Duration d) {
  for (final (dur, label) in _intervals) {
    if (dur == d) return label;
  }
  return d.inSeconds < 60 ? '${d.inSeconds}s' : '${d.inMinutes}m';
}
```

The `_intervalLabel` linear scan + fallback is fine for 5 elements, but
`Map<Duration, String>` makes intent obvious. The fallback formatter is
also unused inside the menu (intervals always match) — only the active
badge needs it. Worth a comment if kept, or drop the fallback.

### Pre-trim `tab.filter`/`selectList`/`orderBy` once

`TableView` calls `tab.filter.trim()` multiple times in the same build
(table_view.dart:246-248). Cheap, but reads cleanly if computed once into
locals. Same for `_TableToolbar.build` reading `tab.filter` / `tab.orderBy`
both at l.238-242 and l.246-248.

### `Workspace._content` uses `ValueKey(tab.id)` defensively

```dart
Widget _content(WorkspaceTab tab) {
  final key = ValueKey(tab.id);
  return switch (tab) { … };
}
```

Each child widget already takes `key`, but they're stored inside an
`IndexedStack` whose children are positional. Reordering tabs would re-key
in place — which is what you want. Leaves a question: is the
`IndexedStack` index-stable when tabs are closed? `closeTab` mutates the
list by `removeAt`, which shifts indices; the `key` ensures Flutter
re-uses the correct subtree. Good — but worth a single-line comment so a
future reader doesn't "simplify" the keys away.

### `_TabState._tabIcon` falls through `_` case for `TableTab`

```dart
// workspace.dart:190
IconData get _tabIcon => switch (widget.tab) {
      QueryTab() => Icons.terminal,
      SchemaTab() => Icons.data_object,
      _ => Icons.table_rows_outlined,
    };
```

`WorkspaceTab` is `sealed`. The `_` case defeats the compiler's
exhaustiveness check — if a fourth subtype is added, this returns the
table icon silently. Make it explicit:

```dart
IconData get _tabIcon => switch (widget.tab) {
      QueryTab() => Icons.terminal,
      SchemaTab() => Icons.data_object,
      TableTab() => Icons.table_rows_outlined,
    };
```

The `sealed` declaration in `workspace_tab.dart:6` is then load-bearing for
the analyzer.

### `Introspector._fkAction` returns `null` for `'a'`

```dart
case 'a':
  return null; // NO ACTION — default, suppress
```

The accompanying `onUpdate` / `onDelete` fields are `String?` so this works
— but other callers can't distinguish "no clause" from "missing value".
Consider an enum `FkAction { noAction, restrict, cascade, setNull, setDefault }`
with a sentinel for "absent". Optional; today the null-as-no-action is
contained to DDL string assembly.

### `parseSqlStatements` is called twice in `_runAll`

```dart
// query_editor.dart:135
final stmts = _statements.isNotEmpty
    ? _statements
    : parseSqlStatements(_controller.text);
```

`_recomputeStatements()` is wired to every controller change, so
`_statements` is *never* empty if the buffer has anything in it. The
fallback is dead code; the `if (stmts.length <= 1)` branch covers the
single-statement case already. Delete the ternary, use `_statements`
directly.

---

## Patterns worth codifying as project conventions

These are recurring shapes good enough to put in `CLAUDE.md` so future code
follows them automatically.

1. **`Object?` not `dynamic` for Postgres cell values.** Already what the
   driver returns. Forces explicit `is` narrowing at use sites; lints catch
   "fell through to toString" mistakes.

2. **`Hoverable` for any tap target with a hover state.** Most widgets in
   the codebase need exactly the `(_hover) => …` pattern; centralising
   removes ~600 lines and a recurring source of "did I dispose the
   MouseRegion subscription" worries.

3. **Cell value → SQL fragment helpers live in `value_format.dart` or
   adjacent.** Currently spread across `AppState` and `TableView`.
   `formatCellValue` is already there; add `equalityFragment`.

4. **Prefer `firstWhereOrNull` (collection) over `firstWhere` + sentinel.**
   Already used pervasively as plain `firstWhere(_, orElse: () => …)`;
   sentinels are an antipattern in a codebase that's chosen `sealed` /
   exhaustive `switch` elsewhere.

5. **Don't catch generic `Object` / unspecified.** The `connect` /
   `runQuery` / `applyTableEdits` paths catch everything; narrow to
   `Exception` plus the driver's `ServerException` (which is already done
   in `postgres_service.dart`, just inconsistently).

6. **Snackbar wrapper.** Three call sites build the same `SnackBar(
   backgroundColor: AppColors.surfaceAlt, content: Text(…, AppTheme.mono(…)) )`
   shell (`schema_view.dart:43`, `table_view.dart:216`,
   `export_dialog.dart:142`). One helper `showAppSnack(context, message,
   {error: false})` collapses them.

7. **Exhaustive `switch` over `sealed`, no `_` default.** Already used in
   `cell_picker._kindFor` (good); the `_TabState._tabIcon` regression in
   `workspace.dart:190` shows the discipline isn't applied uniformly.

8. **No widget-tree work in build that mutates other widgets' state.**
   `_TableToolbar.build` writes to `TextEditingController.text` (l.235-243).
   Move to `didChangeDependencies` or a listener.

---

## Summary

The codebase is *cleaner than its size suggests*: zero analyzer issues,
zero TODOs, dispose discipline is observed, sealed classes + exhaustive
switches are used where it matters, and the comments mostly explain *why*
(per CLAUDE.md). The frame budget on the grid has clearly been thought
through — `RepaintBoundary`, `addAutomaticKeepAlives: false`, single
`Listener` for hit-test, `ValueNotifier` for selection. That work is real
and shows in the code.

The two biggest wins are mechanical:

1. **Introduce `Hoverable`** in `ui/widgets/common.dart` and migrate the
   20 sites. -600 LOC and one fewer pattern to keep in your head.

2. **Replace `dynamic` with `Object?`** on cell-value paths
   (`formatCellValue`, callbacks on `ResultsGrid`, `AppState` helpers).
   No behavior change; the analyzer starts catching anything that
   forgets to narrow.

After those two, the cell_picker file split (#2) and the dedup of
`equalityFragment` / `_listEq` / filename-timestamp (#4, #6, #7) are
small, mechanical, and remove genuine copy-paste — they pass the
CLAUDE.md test of "removes duplication that already exists".

Everything else is polish.

— code-quality reviewer
