---
name: persist-connection-field
description: Use when adding a new persisted field to ConnectionConfig (favorites, recent items, per-connection preferences, …). Covers the full path from model → JSON → AppState mutation → hydration on connect.
---

The connection-level config in `lib/models/connection_config.dart` is
the canonical place for **per-connection persisted state**. Examples
already there: `favoriteTables`, `savedQueries`, `recentTables`,
`columnWidths`, `lastConnectedAt`. Adding a new one follows the same
six-step pattern.

## 1. Add the field to `ConnectionConfig`

Make the parameter optional in the constructor and use the
empty-collection / null default so old config files load cleanly:

```dart
ConnectionConfig({
  …
  List<MyThing>? myCollection,
}) : myCollection = myCollection ?? const [];

final List<MyThing> myCollection;
```

If the type is a `Set` or `Map`, use the same `const {}` / `const {}`
default.

## 2. Update `toJson`

Skip empty values so the JSON stays small:

```dart
if (myCollection.isNotEmpty) 'myCollection': [
  for (final m in myCollection) m.toJson()
],
```

For primitive collections you can drop them directly.

## 3. Update `fromJson`

Defensive parsing — every branch must handle the absent / wrong-shape
case by returning the default:

```dart
myCollection: j['myCollection'] is List
    ? [
        for (final m in j['myCollection'] as List)
          MyThing.fromJson(m as Map<String, dynamic>),
      ]
    : null,
```

## 4. Update `copyWith`

Same shape — accept an optional new value, fall back to `this.x`:

```dart
ConnectionConfig copyWith({
  …
  List<MyThing>? myCollection,
}) => ConnectionConfig(
  id: id,
  …
  myCollection: myCollection ?? this.myCollection,
);
```

## 5. Use `_replaceActiveConnection` in AppState

Never reach into `_connections` directly to update a field. The
canonical mutate-and-persist path:

```dart
void doThing(MyThing item) {
  final conn = _activeConnection;
  if (conn == null) return;
  final next = [...conn.myCollection, item];
  _replaceActiveConnection(conn.copyWith(myCollection: next));
}
```

`_replaceActiveConnection` finds the connection in `_connections`,
swaps it, updates `_activeConnection`, calls `_persist()`, and
`notifyListeners()`.

For frequent updates (e.g. debounced autosave, resize drag), use a
`Timer?` field that's `cancel()`'d on each tick and re-scheduled. See
`AppState._widthSaveTimer` / `QueryEditor._saveTimer` for the pattern.

## 6. Hydrate on connect

Some persisted fields need to come back to life when the connection
opens. Examples:

- `recentTables` is `List<String>` (keys), but the UI wants `List<DbTable>`.
  `_hydrateRecents` resolves keys back to objects after `loadSchemas`.
- `columnWidths` is `Map<schema.table, Map<column, width>>`. `openTable`
  hydrates the newly-created `TableTab.columnWidths` from it.

Pick the right hook:
- Resolve from the loaded **catalog** → do it in `connect()` after
  `loadSchemas()` returns (see `_hydrateRecents`).
- Apply when the **tab opens** → do it in `openTable` after creating
  the tab (see `openTable`'s `savedWidths` block).

## Checklist

- [ ] Field added to `ConnectionConfig` constructor + final
- [ ] `toJson` skips empty values
- [ ] `fromJson` handles absent + wrong-shape input
- [ ] `copyWith` accepts the new field
- [ ] Mutations go through `_replaceActiveConnection`
- [ ] Hydration runs at the right hook (connect vs openTable)
- [ ] Manually delete `~/Library/Containers/<bundle>/Data/Library/Application Support/<bundle>/connections.json`
       and reconnect to verify the field reloads correctly
- [ ] `verify-changes` passes
