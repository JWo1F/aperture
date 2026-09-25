import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/db_catalog.dart';
import '../models/db_object.dart';
import '../services/db_service.dart';

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

  /// True once phase 0 has populated the schema list — i.e. the sidebar
  /// can stop showing the initial-load spinner. False both before the first
  /// successful phase-0 fetch and after [reset] clears the catalog.
  bool get hasSchemas => _catalog.hasPhase(CatalogPhase.schemas);

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
  /// Failures land on [lastError] so the sidebar can distinguish "couldn't
  /// load schemas" from a legitimately empty database.
  Future<List<DbSchema>?> runPhase0(DbService service, int gen) async {
    try {
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
    } catch (e) {
      if (gen == _generation) {
        _lastError = e;
        notifyListeners();
      }
      return null;
    }
  }

  /// Bump the generation, fetch phase 0, then either await or background
  /// phase 1. Returns the phase-0 schema list, or null if the fetch
  /// failed or a newer generation superseded this load.
  Future<List<DbSchema>?> load(
    DbService service, {
    required bool awaitPhase1,
  }) async {
    final gen = beginGeneration();
    final schemas = await runPhase0(service, gen);
    if (schemas == null) return null;
    if (awaitPhase1) {
      await runPhase1(service, gen);
    } else {
      unawaited(runPhase1(service, gen));
    }
    return schemas;
  }

  /// Run phase 1 (columns / FKs / keys / indexes / enums / domains /
  /// routines / sequences) under [gen]. The sweeps run in parallel; any error
  /// leaves the catalog in its phase-0 state and surfaces on [lastError].
  ///
  /// Every mutation of controller-owned state (loading flag, lastError,
  /// catalog) is guarded by a fresh generation check. A stale success must
  /// not clear a newer connection's error, and a stale failure must not
  /// overwrite it — the user clicking "connect" while a slow phase-1 is
  /// in flight should see only the new connection's outcome.
  Future<void> runPhase1(DbService service, int gen) async {
    if (gen != _generation) return;
    _phase1Loading = true;
    _lastError = null;
    notifyListeners();
    final introspector = service.introspector;
    try {
      final results = await Future.wait([
        introspector.loadAllColumns(),
        introspector.loadAllForeignKeys(),
        introspector.loadAllKeys(),
        introspector.loadAllIndexes(),
        introspector.loadAllEnums(),
        introspector.loadAllDomains(),
        introspector.loadAllRoutines(),
        introspector.loadAllSequences(),
      ]);
      if (gen != _generation) return;
      _catalog = _catalog.copyWith(
        columnsByOid: results[0] as Map<int, List<DbColumn>>,
        foreignKeysByOid: results[1] as Map<int, List<DbForeignKey>>,
        keysByOid: results[2] as Map<int, List<DbKey>>,
        indexesByOid: results[3] as Map<int, List<DbIndex>>,
        enums: results[4] as List<DbEnum>,
        domains: results[5] as List<DbDomain>,
        routines: results[6] as List<DbRoutine>,
        sequences: results[7] as List<DbSequence>,
        phases: {
          ..._catalog.phases,
          CatalogPhase.columns,
          CatalogPhase.foreignKeys,
          CatalogPhase.keys,
          CatalogPhase.indexes,
          CatalogPhase.enums,
          CatalogPhase.domains,
          CatalogPhase.routines,
          CatalogPhase.sequences,
        },
      );
    } catch (e) {
      if (gen != _generation) return;
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
