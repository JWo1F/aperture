---
name: add-postgres-query
description: Use when adding any new query that hits pg_catalog (pg_class, pg_attribute, pg_constraint, pg_index, pg_namespace, …) or runs through the extended query protocol. Captures the codec / type-cast gotchas that crash the app silently if you forget them.
---

The `postgres` package (3.x) operates in **extended query mode** by
default. It has codecs for the common Postgres types but **not** for
internal catalog types. Three things to remember on every new query:

## 1. `name`-typed columns need `::text`

Anything in pg_catalog that's the `name` type (OID 19) — `relname`,
`attname`, `nspname`, `conname`, `indexname`, `tablename`, … — comes back
as `UndecodedBytes`, not `String`. Casting to `String` crashes with
`'UndecodedBytes' is not a subtype of type 'String'`.

**Always add explicit `::text` casts in SQL:**

```dart
'SELECT a.attname::text, format_type(a.atttypid, a.atttypmod), '
'NOT a.attnotnull, '
'pg_get_expr(d.adbin, d.adrelid), '
'col_description(a.attrelid, a.attnum) '
'FROM pg_attribute a …'
```

`format_type`, `pg_get_constraintdef`, `pg_get_expr`, `col_description`,
`obj_description` all already return `text` — no cast needed.

`contype` is the `char` type — also cast `::text` to be safe.

## 2. Use parameters for user input — never string interpolation

```dart
final result = await _conn.execute(
  Sql.named('SELECT … WHERE schemaname = @schema AND tablename = @table'),
  parameters: {'schema': schema, 'table': table},
);
```

But — `pg_class` / `pg_constraint` / `pg_index` etc. accept a `regclass`
literal which is easier to build via `'"schema"."table"'::regclass`. In
that case build the regclass safely:

```dart
final regclass =
    "'${_quoteIdent(table.schema)}.${_quoteIdent(table.name)}'::regclass";
```

`_quoteIdent` lives in `PostgresService` — doubles embedded quotes.

## 3. Multi-statement scripts can't go through extended query

A single `_conn.execute('SELECT 1; SELECT 2;')` fails with
`"cannot insert multiple commands into a prepared statement"`.

For user-supplied SQL that might contain multiple statements, parse with
`parseSqlStatements` and run each via
`runQuery(tab, sqlOverride: stmt.text)` in sequence. See
`query_editor.dart`'s `_runAll` for the canonical example.

## Where to put the query

- **Schema introspection / metadata** lives in `PostgresService` (e.g.
  `loadColumns`, `loadForeignKeys`, `loadTableDdl`).
- The **service exposes typed methods**, not raw SQL — convert the row
  set into your domain model (`DbColumn`, `DbForeignKey`, …) before
  returning. Callers shouldn't see `ResultRow`s.
- **Cache the result in AppState** if it's per-table or per-connection
  (see `_columnCache`, `_fkCache`). `ensureColumns` is the canonical
  load-once-per-table pattern.

## Checklist

- [ ] Cast every `name`-typed selected column to `::text`
- [ ] Cast `char`-typed columns (`contype`, etc.) to `::text` too
- [ ] Parameterise user-supplied values via `Sql.named`
- [ ] If single-statement, fine for extended protocol; if multi, split first
- [ ] Convert rows to domain types before returning from the service
- [ ] Cache in AppState if the result is per-(connection, table)
- [ ] Run `verify-changes` against a real Postgres before committing
