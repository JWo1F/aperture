import 'package:aperture/models/db_object.dart';
import 'package:aperture/services/db_service.dart';
import 'package:aperture/services/keychain.dart';
import 'package:aperture/state/app_globals.dart';
import 'package:aperture/state/app_state.dart';
import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/ui/workspace/object_view/info_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _customers = DbTable(
  oid: 1,
  schema: 'public',
  name: 'customers',
  kind: DbRelationKind.table,
);
final _orders = DbTable(
  oid: 2,
  schema: 'public',
  name: 'orders',
  kind: DbRelationKind.table,
  comment: 'Every order a customer placed.',
  rowEstimate: 1200000,
  sizeBytes: 240 * 1024 * 1024,
);

class _Catalog implements Introspector {
  @override
  Future<List<DbSchema>> loadSchemas() async => [
    DbSchema(name: 'public', tables: [_customers, _orders]),
  ];

  @override
  Future<Map<int, List<DbColumn>>> loadAllColumns() async => {
    2: [
      DbColumn(
        name: 'id',
        dataType: 'bigint',
        nullable: false,
        isPrimaryKey: true,
        hasDefault: true,
        ordinal: 1,
      ),
      DbColumn(
        name: 'customer_id',
        dataType: 'integer',
        nullable: false,
        isPrimaryKey: false,
        hasDefault: false,
        ordinal: 2,
      ),
      DbColumn(
        name: 'total',
        dataType: 'numeric(10,2)',
        nullable: true,
        isPrimaryKey: false,
        hasDefault: false,
        ordinal: 3,
        comment: 'Order total in euros.',
      ),
    ],
  };

  @override
  Future<Map<int, List<DbForeignKey>>> loadAllForeignKeys() async => {
    2: [
      DbForeignKey(
        constraintName: 'orders_customer_id_fkey',
        localColumns: ['customer_id'],
        refSchema: 'public',
        refTable: 'customers',
        refTableOid: 1,
        refColumns: ['id'],
      ),
    ],
  };

  @override
  Future<Map<int, List<DbKey>>> loadAllKeys() async => {};

  @override
  Future<Map<int, List<DbIndex>>> loadAllIndexes() async => {
    2: [
      DbIndex(name: 'orders_pkey', columns: ['id'], unique: true, def: ''),
    ],
  };

  @override
  Future<List<DbEnum>> loadAllEnums() async => [];
  @override
  Future<List<DbDomain>> loadAllDomains() async => [];
  @override
  Future<List<DbRoutine>> loadAllRoutines() async => [];
  @override
  Future<List<DbSequence>> loadAllSequences() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service implements DbService {
  @override
  Introspector get introspector => _Catalog();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoKeychain extends Keychain {
  @override
  Future<String?> readPassphrase() async => null;
}

void main() {
  setUpAll(() async {
    appState = AppState(keychain: _NoKeychain(), storePath: '/dev/null');
    final gen = appState.catalog.beginGeneration();
    await appState.catalog.runPhase0(_Service(), gen);
    await appState.catalog.runPhase1(_Service(), gen);
  });
  tearDown(() => AppColors.setPalette(darkPalette));

  for (final (name, palette) in [
    ('dark', darkPalette),
    ('light', lightPalette),
  ]) {
    for (final width in [640.0, 1200.0]) {
      testWidgets('describes a table in plain words ($name, $width px)', (
        tester,
      ) async {
        AppColors.setPalette(palette);
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: Material(child: InfoBody(table: _orders)),
          ),
        );

        expect(find.text('Every order a customer placed.'), findsOneWidget);
        expect(find.textContaining('≈1.2M rows'), findsOneWidget);
        expect(find.text('Whole number (large)'), findsOneWidget);
        expect(find.text('Exact number, 2 decimal places'), findsOneWidget);
        expect(find.text('Identifies each row'), findsOneWidget);
        expect(find.text('Points to customers'), findsOneWidget);
        expect(find.text('Order total in euros.'), findsOneWidget);
        expect(
          find.textContaining('Each row points to a row in customers'),
          findsOneWidget,
        );
        expect(find.text('No two rows can share the same id'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
