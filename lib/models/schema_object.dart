import 'db_object.dart';

/// Anything the object tab can show: a relation, a routine, a sequence or a
/// user type. Only relations have an info page; everything has DDL.
sealed class SchemaObject {
  const SchemaObject();

  String get schema;
  String get name;

  /// What to call the object in prose — "table", "materialized view", … .
  String get kindLabel;

  /// Stable identity, so opening the same object twice reuses its tab.
  String get key;
}

class RelationObject extends SchemaObject {
  const RelationObject(this.table);
  final DbTable table;

  @override
  String get schema => table.schema;
  @override
  String get name => table.name;
  @override
  String get kindLabel => switch (table.kind) {
    DbRelationKind.table when table.partitioned => 'partitioned table',
    DbRelationKind.table => 'table',
    DbRelationKind.view => 'view',
    DbRelationKind.materializedView => 'materialized view',
  };
  @override
  String get key => 'rel:${table.qualifiedKey}';
}

class RoutineObject extends SchemaObject {
  const RoutineObject(this.routine);
  final DbRoutine routine;

  @override
  String get schema => routine.schema;
  @override
  String get name => routine.name;
  @override
  String get kindLabel => switch (routine.kind) {
    DbRoutineKind.function => 'function',
    DbRoutineKind.procedure => 'procedure',
  };
  @override
  String get key => 'routine:${routine.oid}';
}

class SequenceObject extends SchemaObject {
  const SequenceObject(this.sequence);
  final DbSequence sequence;

  @override
  String get schema => sequence.schema;
  @override
  String get name => sequence.name;
  @override
  String get kindLabel => 'sequence';
  @override
  String get key => 'seq:${sequence.oid}';
}

class EnumObject extends SchemaObject {
  const EnumObject(this.type);
  final DbEnum type;

  @override
  String get schema => type.schema;
  @override
  String get name => type.name;
  @override
  String get kindLabel => 'enum type';
  @override
  String get key => 'enum:${type.qualifiedKey}';
}

class DomainObject extends SchemaObject {
  const DomainObject(this.domain);
  final DbDomain domain;

  @override
  String get schema => domain.schema;
  @override
  String get name => domain.name;
  @override
  String get kindLabel => 'domain';
  @override
  String get key => 'domain:${domain.schema}.${domain.name}';
}
