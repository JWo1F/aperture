import 'package:flutter/foundation.dart';

import '../models/db_catalog.dart';
import '../models/db_object.dart';
import '../services/postgres_service.dart';

/// Live introspected catalog (schemas, columns, FKs, indexes, enums,
/// domains) plus the generation counter that guards background loads.
///
/// Loads run in two phases. Phase 0 (schemas) blocks the sidebar's first
/// paint; phase 1 (everything else) runs in the background. Every
/// in-flight load compares against the generation it was launched under
/// before merging results, so a connection switch during loading discards
/// late arrivals.
class CatalogController extends ChangeNotifier {
  DatabaseCatalog _catalog = DatabaseCatalog.empty;
  int _generation = 0;
  bool _phase1Loading = false;
  Object? _lastError;

  DatabaseCatalog get catalog => _catalog;

  List<DbSchema> get schemas => _catalog.schemas;

  int get generation => _generation;

  bool get isPhase1Loading => _phase1Loading;

  Object? get lastError => _lastError;

  /// Bumps the generation counter, clears the catalog, and returns the new
  /// generation. Callers thread this value through subsequent introspection
  /// awaits and check it on completion before merging.
  int beginGeneration() {
    _generation++;
    _catalog = DatabaseCatalog.empty;
    _phase1Loading = false;
    _lastError = null;
    notifyListeners();
    return _generation;
  }

  /// Run phase 0 (schemas only) under [gen]. Late arrivals are dropped.
  Future<List<DbSchema>?> runPhase0(PostgresService service, int gen) async {
    final introspector = service.introspector;
    final schemas = await introspector.loadSchemas();
    if (gen != _generation) return null;
    final relationsByOid = <int, DbTable>{};
    for (final s in schemas) {
      for (final t in s.tables) {
        relationsByOid[t.oid] = t;
      }
    }
    _catalog = DatabaseCatalog.empty.copyWith(
      schemas: schemas,
      relationsByOid: relationsByOid,
      phases: {CatalogPhase.schemas},
    );
    notifyListeners();
    return schemas;
  }

  /// Run phase 1 (columns/FKs/indexes/enums/domains) under [gen]. The five
  /// sweeps run in parallel; any error leaves the catalog in its phase-0
  /// state and surfaces on [lastError].
  Future<void> runPhase1(PostgresService service, int gen) async {
    _phase1Loading = true;
    _lastError = null;
    notifyListeners();
    final introspector = service.introspector;
    try {
      final results = await Future.wait([
        introspector.loadAllColumns(),
        introspector.loadAllForeignKeys(),
        introspector.loadAllIndexes(),
        introspector.loadAllEnums(),
        introspector.loadAllDomains(),
      ]);
      if (gen != _generation) return;
      _catalog = _catalog.copyWith(
        columnsByOid: results[0] as Map<int, List<DbColumn>>,
        foreignKeysByOid: results[1] as Map<int, List<DbForeignKey>>,
        indexesByOid: results[2] as Map<int, List<DbIndex>>,
        enums: results[3] as List<DbEnum>,
        domains: results[4] as List<DbDomain>,
        phases: {
          ..._catalog.phases,
          CatalogPhase.columns,
          CatalogPhase.foreignKeys,
          CatalogPhase.indexes,
          CatalogPhase.enums,
          CatalogPhase.domains,
        },
      );
    } catch (e) {
      _lastError = e;
    } finally {
      if (gen == _generation) {
        _phase1Loading = false;
        notifyListeners();
      }
    }
  }

  /// Reset to the empty catalog. Used on disconnect.
  void reset() {
    _generation++;
    _catalog = DatabaseCatalog.empty;
    _phase1Loading = false;
    _lastError = null;
    notifyListeners();
  }

  // --- Lookup helpers used by tabs / cell context menus ----------------

  List<DbColumn>? columnsFor(DbTable table) {
    final cols = _catalog.columnsByOid[table.oid];
    return (cols == null || cols.isEmpty) ? null : cols;
  }

  Map<String, DbForeignKey>? foreignKeysFor(DbTable table) {
    if (!_catalog.hasPhase(CatalogPhase.foreignKeys)) return null;
    return _catalog.singleColumnForeignKeysFor(table);
  }

  Map<String, DbForeignKey> get aggregatedForeignKeys =>
      _catalog.aggregatedSingleColumnForeignKeys;

  DbForeignKey? findForeignKey(int? sourceRelOid, String columnName) {
    if (sourceRelOid == null || sourceRelOid == 0) return null;
    final fks = _catalog.foreignKeysByOid[sourceRelOid];
    if (fks == null) return null;
    for (final fk in fks) {
      if (fk.isSingleColumn && fk.localColumn == columnName) return fk;
    }
    return null;
  }

  DbTable? findPrimaryKeyOwner(String columnName) =>
      _catalog.findUniquePrimaryKeyOwner(columnName);

  DbTable? findPrimaryKeyOwnerByOid(int? sourceRelOid, String columnName) {
    if (sourceRelOid == null || sourceRelOid == 0) {
      return findPrimaryKeyOwner(columnName);
    }
    final cols = _catalog.columnsByOid[sourceRelOid];
    if (cols == null) return findPrimaryKeyOwner(columnName);
    for (final c in cols) {
      if (c.name == columnName) {
        if (c.isPrimaryKey) return _catalog.relation(sourceRelOid);
        return findPrimaryKeyOwner(columnName);
      }
    }
    return findPrimaryKeyOwner(columnName);
  }

  DbTable? relation(int oid) => _catalog.relation(oid);

  DbTable? relationByName(String schema, String table) =>
      _catalog.relationByName(schema, table);

  Iterable<String> get allColumnNames => _catalog.allColumnNames;
}
