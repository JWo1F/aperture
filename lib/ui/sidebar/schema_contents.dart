import '../../models/db_catalog.dart';
import '../../models/db_object.dart';

/// One schema's objects, bucketed the way the tree shows them.
class SchemaContents {
  SchemaContents({
    required this.schema,
    required this.tables,
    required this.partitioned,
    required this.views,
    required this.materializedViews,
    required this.functions,
    required this.procedures,
    required this.sequences,
    required this.enums,
    required this.domains,
  });

  final DbSchema schema;
  final List<DbTable> tables;
  final List<DbTable> partitioned;
  final List<DbTable> views;
  final List<DbTable> materializedViews;
  final List<DbRoutine> functions;
  final List<DbRoutine> procedures;
  final List<DbSequence> sequences;
  final List<DbEnum> enums;
  final List<DbDomain> domains;

  int get count =>
      tables.length +
      partitioned.length +
      views.length +
      materializedViews.length +
      functions.length +
      procedures.length +
      sequences.length +
      enums.length +
      domains.length;
}

/// Buckets every schema's objects, keeping only those whose name or schema
/// contains [query] (already lower-cased; empty keeps everything). A
/// filtered-out schema is dropped when nothing in it survives.
///
/// Relations define the schema list, but a schema holding only functions or
/// types has no relations — those schemas are appended so their objects
/// still have somewhere to live.
List<SchemaContents> groupSchemaContents(
  DatabaseCatalog catalog,
  String query,
) {
  bool matches(String schema, String name) =>
      query.isEmpty ||
      name.toLowerCase().contains(query) ||
      schema.toLowerCase().contains(query);

  Map<String, List<T>> bySchema<T>(
    List<T> items,
    String Function(T) schema,
    String Function(T) name,
  ) {
    final map = <String, List<T>>{};
    for (final item in items) {
      if (matches(schema(item), name(item))) {
        map.putIfAbsent(schema(item), () => []).add(item);
      }
    }
    return map;
  }

  final routines = bySchema(catalog.routines, (r) => r.schema, (r) => r.name);
  final sequences = bySchema(catalog.sequences, (q) => q.schema, (q) => q.name);
  final enums = bySchema(catalog.enums, (e) => e.schema, (e) => e.name);
  final domains = bySchema(catalog.domains, (d) => d.schema, (d) => d.name);

  final schemas = [...catalog.schemas];
  final known = {for (final s in schemas) s.name};
  final extra = <String>{
    ...routines.keys,
    ...sequences.keys,
    ...enums.keys,
    ...domains.keys,
  }.difference(known).toList()..sort();
  schemas.addAll([
    for (final name in extra) DbSchema(name: name, tables: const []),
  ]);

  final out = <SchemaContents>[];
  for (final s in schemas) {
    final relations = [
      for (final t in s.tables)
        if (matches(t.schema, t.name)) t,
    ];
    final schemaRoutines = routines[s.name] ?? const <DbRoutine>[];
    final contents = SchemaContents(
      schema: s,
      tables: [
        for (final t in relations)
          if (t.kind == DbRelationKind.table && !t.partitioned) t,
      ],
      partitioned: [
        for (final t in relations)
          if (t.partitioned) t,
      ],
      views: [
        for (final t in relations)
          if (t.kind == DbRelationKind.view) t,
      ],
      materializedViews: [
        for (final t in relations)
          if (t.kind == DbRelationKind.materializedView) t,
      ],
      functions: [
        for (final r in schemaRoutines)
          if (r.kind == DbRoutineKind.function) r,
      ],
      procedures: [
        for (final r in schemaRoutines)
          if (r.kind == DbRoutineKind.procedure) r,
      ],
      sequences: sequences[s.name] ?? const [],
      enums: enums[s.name] ?? const [],
      domains: domains[s.name] ?? const [],
    );
    if (query.isEmpty || contents.count > 0) out.add(contents);
  }
  return out;
}
