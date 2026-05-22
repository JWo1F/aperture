import 'package:dbv/models/db_object.dart';
import 'package:dbv/services/db_service.dart';
import 'package:dbv/state/catalog_controller.dart';
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
