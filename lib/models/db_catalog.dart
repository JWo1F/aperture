import 'db_object.dart';

/// Immutable snapshot of everything we've introspected about a live database
/// session. Built incrementally: [phases] tracks which sweeps have landed so
/// the UI can hide features that depend on data not yet present.
///
/// All structured lookups are keyed by relation `oid` so distinct tables that
/// happen to share a name (different schemas) never collide.
class DatabaseCatalog {
  DatabaseCatalog({
    required this.schemas,
    required this.relationsByOid,
    required this.columnsByOid,
    required this.foreignKeysByOid,
    required this.keysByOid,
    required this.indexesByOid,
    required this.enums,
    required this.domains,
    required this.phases,
  });

  /// An empty catalog — placeholder used between disconnect and the first
  /// phase-0 sweep.
  static final empty = DatabaseCatalog(
    schemas: const [],
    relationsByOid: const {},
    columnsByOid: const {},
    foreignKeysByOid: const {},
    keysByOid: const {},
    indexesByOid: const {},
    enums: const [],
    domains: const [],
    phases: const {},
  );

  final List<DbSchema> schemas;
  final Map<int, DbTable> relationsByOid;
  final Map<int, List<DbColumn>> columnsByOid;
  final Map<int, List<DbForeignKey>> foreignKeysByOid;
  final Map<int, List<DbKey>> keysByOid;
  final Map<int, List<DbIndex>> indexesByOid;
  final List<DbEnum> enums;
  final List<DbDomain> domains;
  final Set<CatalogPhase> phases;

  bool hasPhase(CatalogPhase phase) => phases.contains(phase);

  /// Returns the relation matching [oid] across every schema, or null if the
  /// oid isn't in the catalog (yet, or anymore).
  DbTable? relation(int oid) => relationsByOid[oid];

  /// Returns the relation with this exact [schema] + [name], if loaded.
  DbTable? relationByName(String schema, String name) {
    for (final r in relationsByOid.values) {
      if (r.schema == schema && r.name == name) return r;
    }
    return null;
  }

  List<DbColumn> columnsFor(DbTable table) =>
      columnsByOid[table.oid] ?? const [];

  /// Every foreign key of [table], including multi-column constraints.
  List<DbForeignKey> foreignKeysFor(DbTable table) =>
      foreignKeysByOid[table.oid] ?? const [];

  /// Single-column FKs of [table] keyed by their local column name. Multi-
  /// column FKs are dropped here — callers that need the wider shape should
  /// read [foreignKeysByOid] directly.
  Map<String, DbForeignKey> singleColumnForeignKeysFor(DbTable table) {
    final out = <String, DbForeignKey>{};
    final all = foreignKeysByOid[table.oid] ?? const [];
    for (final fk in all) {
      if (fk.isSingleColumn) out[fk.localColumn] = fk;
    }
    return out;
  }

  /// Primary-key and UNIQUE constraints of [table], primary key first.
  List<DbKey> keysFor(DbTable table) => keysByOid[table.oid] ?? const [];

  List<DbIndex> indexesFor(DbTable table) =>
      indexesByOid[table.oid] ?? const [];

  /// First relation whose primary key consists of exactly the single column
  /// [columnName]. Used as a fallback when we don't know the source relation
  /// of a query-result column. Returns null if zero or multiple tables match
  /// — preferring "don't know" over silently picking the wrong one.
  DbTable? findUniquePrimaryKeyOwner(String columnName) {
    DbTable? match;
    for (final entry in columnsByOid.entries) {
      final pks = entry.value.where((c) => c.isPrimaryKey).toList();
      if (pks.length != 1) continue;
      if (pks.first.name != columnName) continue;
      final relation = relationsByOid[entry.key];
      if (relation == null) continue;
      if (match != null) return null;
      match = relation;
    }
    return match;
  }

  /// Every distinct column name we've loaded — fed into SQL editor
  /// autocomplete.
  Iterable<String> get allColumnNames sync* {
    final seen = <String>{};
    for (final cols in columnsByOid.values) {
      for (final c in cols) {
        if (seen.add(c.name)) yield c.name;
      }
    }
  }

  /// Aggregated single-column FKs across all relations, keyed by local
  /// column name. First match wins on collisions — used only as a fallback
  /// when the result-set column's source relation is unknown.
  Map<String, DbForeignKey> get aggregatedSingleColumnForeignKeys {
    final out = <String, DbForeignKey>{};
    for (final fks in foreignKeysByOid.values) {
      for (final fk in fks) {
        if (fk.isSingleColumn) {
          out.putIfAbsent(fk.localColumn, () => fk);
        }
      }
    }
    return out;
  }

  DatabaseCatalog withPhase(CatalogPhase phase) => DatabaseCatalog(
    schemas: schemas,
    relationsByOid: relationsByOid,
    columnsByOid: columnsByOid,
    foreignKeysByOid: foreignKeysByOid,
    keysByOid: keysByOid,
    indexesByOid: indexesByOid,
    enums: enums,
    domains: domains,
    phases: {...phases, phase},
  );

  DatabaseCatalog copyWith({
    List<DbSchema>? schemas,
    Map<int, DbTable>? relationsByOid,
    Map<int, List<DbColumn>>? columnsByOid,
    Map<int, List<DbForeignKey>>? foreignKeysByOid,
    Map<int, List<DbKey>>? keysByOid,
    Map<int, List<DbIndex>>? indexesByOid,
    List<DbEnum>? enums,
    List<DbDomain>? domains,
    Set<CatalogPhase>? phases,
  }) => DatabaseCatalog(
    schemas: schemas ?? this.schemas,
    relationsByOid: relationsByOid ?? this.relationsByOid,
    columnsByOid: columnsByOid ?? this.columnsByOid,
    foreignKeysByOid: foreignKeysByOid ?? this.foreignKeysByOid,
    keysByOid: keysByOid ?? this.keysByOid,
    indexesByOid: indexesByOid ?? this.indexesByOid,
    enums: enums ?? this.enums,
    domains: domains ?? this.domains,
    phases: phases ?? this.phases,
  );
}

/// A single batched introspection step. Each phase, once present in
/// [DatabaseCatalog.phases], guarantees the associated map/list is filled.
enum CatalogPhase {
  /// Schemas + relation list (oid, name, kind, comment).
  schemas,

  /// Columns + comments + PK flags for every relation.
  columns,

  /// All foreign keys across all relations.
  foreignKeys,

  /// Primary-key and UNIQUE constraints for every relation.
  keys,

  /// Indexes for every relation, including constraint-backed ones.
  indexes,

  /// User-defined enum types + their labels.
  enums,

  /// User-defined domain types.
  domains,
}
