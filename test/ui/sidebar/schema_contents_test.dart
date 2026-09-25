import 'package:aperture/models/db_catalog.dart';
import 'package:aperture/models/db_object.dart';
import 'package:aperture/ui/sidebar/schema_contents.dart';
import 'package:flutter_test/flutter_test.dart';

DbTable _rel(
  int oid,
  String schema,
  String name,
  DbRelationKind kind, {
  bool partitioned = false,
}) => DbTable(
  oid: oid,
  schema: schema,
  name: name,
  kind: kind,
  partitioned: partitioned,
);

DbRoutine _fn(int oid, String schema, String name, DbRoutineKind kind) =>
    DbRoutine(oid: oid, schema: schema, name: name, kind: kind, arguments: '');

DatabaseCatalog _catalog() => DatabaseCatalog.empty.copyWith(
  schemas: [
    DbSchema(
      name: 'public',
      tables: [
        _rel(1, 'public', 'users', DbRelationKind.table),
        _rel(2, 'public', 'events', DbRelationKind.table, partitioned: true),
        _rel(3, 'public', 'active_users', DbRelationKind.view),
        _rel(4, 'public', 'daily', DbRelationKind.materializedView),
      ],
    ),
  ],
  routines: [
    _fn(10, 'public', 'touch', DbRoutineKind.function),
    _fn(11, 'public', 'archive', DbRoutineKind.procedure),
    _fn(12, 'util', 'slugify', DbRoutineKind.function),
  ],
  sequences: [DbSequence(oid: 20, schema: 'public', name: 'order_no')],
  enums: [
    DbEnum(schema: 'public', name: 'mood', labels: ['ok', 'sad']),
  ],
  domains: [
    DbDomain(schema: 'public', name: 'email', baseType: 'text', notNull: true),
  ],
);

void main() {
  test('buckets each object kind into its own group', () {
    final public = groupSchemaContents(_catalog(), '').first;

    expect(public.tables.map((t) => t.name), ['users']);
    expect(public.partitioned.map((t) => t.name), ['events']);
    expect(public.views.map((t) => t.name), ['active_users']);
    expect(public.materializedViews.map((t) => t.name), ['daily']);
    expect(public.functions.map((r) => r.name), ['touch']);
    expect(public.procedures.map((r) => r.name), ['archive']);
    expect(public.sequences.map((s) => s.name), ['order_no']);
    expect(public.enums.map((e) => e.name), ['mood']);
    expect(public.domains.map((d) => d.name), ['email']);
    expect(public.count, 9);
  });

  test('a schema with no relations still gets its routines', () {
    final schemas = groupSchemaContents(_catalog(), '');

    expect(schemas.map((s) => s.schema.name), ['public', 'util']);
    expect(schemas.last.functions.map((r) => r.name), ['slugify']);
  });

  test('filtering keeps matches across kinds and drops empty schemas', () {
    final byName = groupSchemaContents(_catalog(), 'user');
    expect(byName.map((s) => s.schema.name), ['public']);
    expect(byName.single.tables.map((t) => t.name), ['users']);
    expect(byName.single.views.map((t) => t.name), ['active_users']);
    expect(byName.single.functions, isEmpty);

    final routineOnly = groupSchemaContents(_catalog(), 'slug');
    expect(routineOnly.single.schema.name, 'util');

    // A schema-name match keeps everything in that schema.
    expect(
      groupSchemaContents(_catalog(), 'util').single.functions,
      hasLength(1),
    );
    expect(groupSchemaContents(_catalog(), 'nothing'), isEmpty);
  });

  test('word initials find snake and kebab case names', () {
    final catalog = DatabaseCatalog.empty.copyWith(
      schemas: [
        DbSchema(
          name: 'public',
          tables: [
            _rel(1, 'public', 'alice_bob', DbRelationKind.table),
            _rel(2, 'public', 'alice-bob', DbRelationKind.table),
            _rel(3, 'public', 'albatross', DbRelationKind.table),
          ],
        ),
      ],
    );
    final hits = groupSchemaContents(catalog, 'ab').single.tables;
    expect(hits.map((t) => t.name), ['alice_bob', 'alice-bob']);
  });
}
