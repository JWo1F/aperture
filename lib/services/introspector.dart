import '../models/db_object.dart';

/// Engine-neutral catalog introspection surface.
///
/// Each method is one batched sweep across the live database; together they
/// build the [DatabaseCatalog] the sidebar and schema tree render from. The
/// Postgres and SQLite services each return their own implementation —
/// [CatalogController] never sees which one it has.
///
/// Engines that have no concept of a given sweep (SQLite has no enums or
/// domains, for instance) return an empty collection rather than throwing.
abstract interface class Introspector {
  /// Every user schema with its relations (tables, views, …). For SQLite,
  /// which has a single flat namespace, this is one synthetic `main` schema.
  Future<List<DbSchema>> loadSchemas();

  /// Columns of every relation, keyed by parent relation id, including
  /// primary-key membership.
  Future<Map<int, List<DbColumn>>> loadAllColumns();

  /// Foreign keys across all relations, grouped by source relation id.
  Future<Map<int, List<DbForeignKey>>> loadAllForeignKeys();

  /// Primary-key and UNIQUE constraints for every relation, keyed by
  /// relation id.
  Future<Map<int, List<DbKey>>> loadAllKeys();

  /// Indexes for every relation, keyed by relation id. Includes the indexes
  /// implicitly created to back primary-key / UNIQUE constraints.
  Future<Map<int, List<DbIndex>>> loadAllIndexes();

  /// User-defined enum types. Empty for engines without enum types.
  Future<List<DbEnum>> loadAllEnums();

  /// User-defined domain types. Empty for engines without domains.
  Future<List<DbDomain>> loadAllDomains();

  /// User-defined functions and procedures, excluding extension members.
  /// Empty for engines without stored routines.
  Future<List<DbRoutine>> loadAllRoutines();

  /// Standalone sequences. Empty for engines without sequences.
  Future<List<DbSequence>> loadAllSequences();

  /// `CREATE` statements for the schema objects above. Only reachable for
  /// objects the matching loader returned, so an engine whose loader is
  /// always empty never sees these calls.
  Future<String> loadRoutineDdl(DbRoutine routine);

  Future<String> loadSequenceDdl(DbSequence sequence);

  Future<String> loadEnumDdl(DbEnum type);

  Future<String> loadDomainDdl(DbDomain domain);
}
