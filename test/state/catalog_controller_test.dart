import 'package:aperture/models/db_object.dart';
import 'package:aperture/services/db_service.dart';
import 'package:aperture/state/catalog_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CatalogController.runPhase0', () {
    test('surfaces introspector failures on lastError', () async {
      final controller = CatalogController();
      final svc = _FakeDbService(_ThrowingIntrospector('boom'));
      final gen = controller.beginGeneration();

      final result = await controller.runPhase0(svc, gen);

      expect(result, isNull);
      expect(controller.lastError, isNotNull);
      expect(controller.lastError.toString(), contains('boom'));
    });

    test('drops late failures from a superseded generation', () async {
      final controller = CatalogController();
      final svc = _FakeDbService(_ThrowingIntrospector('stale'));
      final gen = controller.beginGeneration();
      controller.beginGeneration(); // newer generation in flight

      final result = await controller.runPhase0(svc, gen);

      expect(result, isNull);
      expect(controller.lastError, isNull,
          reason: 'stale errors must not clobber the live generation');
    });
  });

  group('CatalogController.runPhase1', () {
    test('drops late failures from a superseded generation', () async {
      final controller = CatalogController();
      final svc = _FakeDbService(_Phase1ThrowingIntrospector('stale-phase1'));
      final gen = controller.beginGeneration();
      final future = controller.runPhase1(svc, gen);
      controller.beginGeneration(); // supersedes before phase 1 throws
      await future;

      expect(controller.lastError, isNull,
          reason: 'stale phase-1 errors must not clobber the live generation');
    });

    test('stale success path does not clear a fresh generation error',
        () async {
      final controller = CatalogController();
      final emptySvc = _FakeDbService(_EmptyIntrospector());
      // Older generation captured first.
      final staleGen = controller.beginGeneration();
      // Newer generation supersedes and registers its own failure.
      controller.beginGeneration();
      final freshSvc = _FakeDbService(_ThrowingIntrospector('fresh'));
      await controller.runPhase0(freshSvc, controller.generation);
      expect(controller.lastError, isNotNull);

      // Late-arriving phase-1 success for the stale generation.
      await controller.runPhase1(emptySvc, staleGen);

      expect(controller.lastError, isNotNull,
          reason: 'stale phase-1 success must not clear a fresh error');
      expect(controller.lastError.toString(), contains('fresh'));
    });
  });
}

class _EmptyIntrospector implements Introspector {
  @override
  Future<List<DbSchema>> loadSchemas() async => const [];

  @override
  Future<Map<int, List<DbColumn>>> loadAllColumns() async => {};

  @override
  Future<Map<int, List<DbForeignKey>>> loadAllForeignKeys() async => {};

  @override
  Future<Map<int, List<DbKey>>> loadAllKeys() async => {};

  @override
  Future<Map<int, List<DbIndex>>> loadAllIndexes() async => {};

  @override
  Future<List<DbEnum>> loadAllEnums() async => [];

  @override
  Future<List<DbDomain>> loadAllDomains() async => [];
}

class _Phase1ThrowingIntrospector implements Introspector {
  _Phase1ThrowingIntrospector(this.message);

  final String message;

  @override
  Future<List<DbSchema>> loadSchemas() async => const [];

  @override
  Future<Map<int, List<DbColumn>>> loadAllColumns() async =>
      throw StateError(message);

  @override
  Future<Map<int, List<DbForeignKey>>> loadAllForeignKeys() async => {};

  @override
  Future<Map<int, List<DbKey>>> loadAllKeys() async => {};

  @override
  Future<Map<int, List<DbIndex>>> loadAllIndexes() async => {};

  @override
  Future<List<DbEnum>> loadAllEnums() async => [];

  @override
  Future<List<DbDomain>> loadAllDomains() async => [];
}

class _ThrowingIntrospector implements Introspector {
  _ThrowingIntrospector(this.message);

  final String message;

  @override
  Future<List<DbSchema>> loadSchemas() async => throw StateError(message);

  @override
  Future<Map<int, List<DbColumn>>> loadAllColumns() async => {};

  @override
  Future<Map<int, List<DbForeignKey>>> loadAllForeignKeys() async => {};

  @override
  Future<Map<int, List<DbKey>>> loadAllKeys() async => {};

  @override
  Future<Map<int, List<DbIndex>>> loadAllIndexes() async => {};

  @override
  Future<List<DbEnum>> loadAllEnums() async => [];

  @override
  Future<List<DbDomain>> loadAllDomains() async => [];
}

class _FakeDbService implements DbService {
  _FakeDbService(this._introspector);

  final Introspector _introspector;

  @override
  Introspector get introspector => _introspector;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not exercised in this test');
}
