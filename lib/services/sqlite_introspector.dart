import '../models/db_object.dart';
import 'introspector.dart';
import 'sql_identifier.dart';
import 'sqlite_service.dart';

/// Catalog introspection for a SQLite database.
///
/// SQLite has no `pg_catalog`; structure is read from the `sqlite_master`
/// table and the `PRAGMA` family. There is one flat namespace, surfaced as a
/// single synthetic `main` schema, and `sqlite_master.rowid` stands in for
/// the relation `oid` the catalog keys everything by.
///
/// `PRAGMA`-based sweeps are inherently per-relation (N+1), which is fine for
/// a local file; they are run with logging suppressed so the activity log
/// stays focused on user-issued queries.
///
/// One catalog-load pass goes through `loadAllColumns` →
/// `loadAllForeignKeys` → `loadAllKeys` → `loadAllIndexes` in parallel. The
/// raw `_relations()` scan and the per-table `PRAGMA table_info` /
/// `PRAGMA index_list` / `PRAGMA index_info` results are memoised on the
/// introspector instance so each unique PRAGMA hits SQLite exactly once
/// across the whole pass; without this a 200-table file emits ~1k blocking
/// FFI calls per catalog refresh. The cache lives for the lifetime of the
/// introspector — `SqliteService` keeps a single instance per connection
/// (recreated on `connect`), so it stays warm across the four loaders but
/// is reset when the database is reopened.
class SqliteIntrospector implements Introspector {
  SqliteIntrospector(this._db);

  final SqliteService _db;

  List<DbTable>? _relationsCache;
  final Map<String, List<List<Object?>>> _tableInfoCache = {};
  final Map<String, List<List<Object?>>> _indexListCache = {};
  final Map<String, List<List<Object?>>> _indexInfoCache = {};

  /// Every user table/view, with `sqlite_master.rowid` as the relation id.
  /// Internal `sqlite_*` objects are excluded.
  List<DbTable> _relations() {
    final cached = _relationsCache;
    if (cached != null) return cached;
    final rs = _db.select(
      "SELECT rowid, name, type FROM sqlite_master "
      "WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%' "
      'ORDER BY name',
      log: false,
    );
    return _relationsCache = [
      for (final row in rs.rows)
        DbTable(
          oid: row[0] as int,
          schema: 'main',
          name: row[1] as String,
          kind: (row[2] as String) == 'view'
              ? DbRelationKind.view
              : DbRelationKind.table,
        ),
    ];
  }

  List<List<Object?>> _tableInfo(String name) {
    return _tableInfoCache.putIfAbsent(
      name,
      () => _db
          .select('PRAGMA table_info(${quoteIdent(name)})', log: false)
          .rows
          .map((r) => r.toList())
          .toList(),
    );
  }

  List<List<Object?>> _indexList(String name) {
    return _indexListCache.putIfAbsent(
      name,
      () => _db
          .select('PRAGMA index_list(${quoteIdent(name)})', log: false)
          .rows
          .map((r) => r.toList())
          .toList(),
    );
  }

  List<List<Object?>> _indexInfo(String name) {
    return _indexInfoCache.putIfAbsent(
      name,
      () => _db
          .select('PRAGMA index_info(${quoteIdent(name)})', log: false)
          .rows
          .map((r) => r.toList())
          .toList(),
    );
  }

  @override
  Future<List<DbSchema>> loadSchemas() async {
    final relations = _relations();
    if (relations.isEmpty) return const [];
    return [DbSchema(name: 'main', tables: relations)];
  }

  @override
  Future<Map<int, List<DbColumn>>> loadAllColumns() async {
    final out = <int, List<DbColumn>>{};
    for (final table in _relations()) {
      // Columns: cid, name, type, notnull, dflt_value, pk.
      out[table.oid] = [
        for (final row in _tableInfo(table.name))
          DbColumn(
            name: row[1] as String,
            dataType: (row[2] as String?) ?? '',
            nullable: (row[3] as int) == 0,
            hasDefault: row[4] != null,
            ordinal: (row[0] as int) + 1,
            isPrimaryKey: (row[5] as int) != 0,
          ),
      ];
    }
    return out;
  }

  @override
  Future<Map<int, List<DbForeignKey>>> loadAllForeignKeys() async {
    final relations = _relations();
    final oidByName = {for (final r in relations) r.name: r.oid};
    final out = <int, List<DbForeignKey>>{};
    for (final table in relations) {
      final rows = _db
          .select(
            'PRAGMA foreign_key_list(${quoteIdent(table.name)})',
            log: false,
          )
          .rows;
      if (rows.isEmpty) continue;
      // Columns: id, seq, table, from, to, on_update, on_delete, match.
      // Rows sharing an `id` form one (possibly multi-column) constraint.
      final byId = <int, List<List<Object?>>>{};
      for (final row in rows) {
        byId.putIfAbsent(row[0] as int, () => []).add(row);
      }
      final fks = <DbForeignKey>[];
      for (final entry in byId.entries) {
        final group = entry.value
          ..sort((a, b) => (a[1] as int).compareTo(b[1] as int));
        final refTable = group.first[2] as String;
        final localCols = [for (final r in group) r[3] as String];
        final refCols = [for (final r in group) r[4] as String?];
        // A null `to` means the FK targets the parent's primary key
        // implicitly; without an explicit column we can't drive the
        // follow-FK gesture, so skip those constraints.
        if (refCols.any((c) => c == null)) continue;
        fks.add(
          DbForeignKey(
            constraintName: 'fk_${table.name}_${entry.key}',
            localColumns: localCols,
            refTableOid: oidByName[refTable] ?? DbTable.unknownOid,
            refSchema: 'main',
            refTable: refTable,
            refColumns: [for (final c in refCols) c!],
            onUpdate: _fkAction(group.first[5] as String?),
            onDelete: _fkAction(group.first[6] as String?),
          ),
        );
      }
      if (fks.isNotEmpty) out[table.oid] = fks;
    }
    return out;
  }

  @override
  Future<Map<int, List<DbKey>>> loadAllKeys() async {
    final out = <int, List<DbKey>>{};
    for (final table in _relations()) {
      final keys = <DbKey>[];
      // Columns: seq, name, unique, origin, partial. `origin` is 'pk' for the
      // primary key, 'u' for a UNIQUE constraint, 'c' for an explicit index.
      for (final row in _indexList(table.name)) {
        final origin = row[3];
        if (origin != 'pk' && origin != 'u') continue;
        final name = row[1] as String;
        final cols = [
          for (final ir in _indexInfo(name))
            if (ir[2] != null) ir[2] as String,
        ];
        if (cols.isEmpty) continue;
        keys.add(
          DbKey(
            name: name,
            kind: origin == 'pk' ? DbKeyKind.primary : DbKeyKind.unique,
            columns: cols,
          ),
        );
      }
      // A single-column INTEGER PRIMARY KEY is a rowid alias with no backing
      // index, so it never shows up in `index_list` — recover it from
      // `table_info` (column 5 is the 1-based position within the PK).
      if (!keys.any((k) => k.isPrimary)) {
        final pkRows = [
          for (final r in _tableInfo(table.name))
            if ((r[5] as int) != 0) r,
        ]..sort((a, b) => (a[5] as int).compareTo(b[5] as int));
        if (pkRows.isNotEmpty) {
          keys.insert(
            0,
            DbKey(
              name: '${table.name}_pk',
              kind: DbKeyKind.primary,
              columns: [for (final r in pkRows) r[1] as String],
            ),
          );
        }
      }
      if (keys.isNotEmpty) out[table.oid] = keys;
    }
    return out;
  }

  @override
  Future<Map<int, List<DbIndex>>> loadAllIndexes() async {
    // Verbatim `CREATE INDEX` text, keyed by index name. Auto-indexes
    // (PK/UNIQUE-backed) carry a null `sql` and so come back with empty def.
    final defByName = <String, String>{
      for (final row in _db
          .select(
            "SELECT name, sql FROM sqlite_master WHERE type = 'index'",
            log: false,
          )
          .rows)
        if (row[1] != null) row[0] as String: row[1] as String,
    };

    final out = <int, List<DbIndex>>{};
    for (final table in _relations()) {
      // Columns: seq, name, unique, origin, partial. Every index is kept,
      // including the auto-indexes backing PK / UNIQUE constraints.
      final indexes = <DbIndex>[];
      for (final row in _indexList(table.name)) {
        final name = row[1] as String;
        indexes.add(
          DbIndex(
            name: name,
            unique: (row[2] as int) != 0,
            def: defByName[name] ?? '',
            columns: [
              for (final ir in _indexInfo(name))
                if (ir[2] != null) ir[2] as String,
            ],
          ),
        );
      }
      if (indexes.isNotEmpty) out[table.oid] = indexes;
    }
    return out;
  }

  /// SQLite has no enum types.
  @override
  Future<List<DbEnum>> loadAllEnums() async => const [];

  /// SQLite has no domain types.
  @override
  Future<List<DbDomain>> loadAllDomains() async => const [];

  /// Normalises a `PRAGMA foreign_key_list` action string. `NO ACTION` is
  @override
  Future<List<DbRoutine>> loadAllRoutines() async => const [];

  @override
  Future<List<DbSequence>> loadAllSequences() async => const [];

  @override
  Future<String> loadRoutineDdl(DbRoutine routine) =>
      throw UnsupportedError('SQLite has no stored routines');

  @override
  Future<String> loadSequenceDdl(DbSequence sequence) =>
      throw UnsupportedError('SQLite has no sequences');

  @override
  Future<String> loadEnumDdl(DbEnum type) =>
      throw UnsupportedError('SQLite has no enum types');

  @override
  Future<String> loadDomainDdl(DbDomain domain) =>
      throw UnsupportedError('SQLite has no domains');

  /// the default and is suppressed (matching the Postgres introspector,
  /// which returns null for it).
  static String? _fkAction(String? raw) {
    if (raw == null) return null;
    final v = raw.toUpperCase();
    return v == 'NO ACTION' ? null : v;
  }
}
