import 'package:dbv/models/connection_config.dart';
import 'package:dbv/models/saved_query.dart';
import 'package:dbv/ui/connection/dialog/connection_form_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('editing a connection preserves per-connection bags', () {
    final existing = ConnectionConfig(
      id: 'c1',
      name: 'Prod',
      host: 'prod.example.com',
      port: 5432,
      database: 'app',
      username: 'alice',
      credential: const PlainCredential('old-pw'),
      favoriteTables: {'public.users'},
      savedQueries: [
        SavedQuery(
          id: 'q1',
          name: 'recent signups',
          sql: 'select * from users limit 50',
        ),
      ],
      recentTables: ['public.users'],
      tableUseCounts: {'public.users': 7},
      columnWidths: {
        'public.users': {'id': 60, 'email': 240},
      },
      lastConnectedAt: DateTime(2026, 5, 1),
    );

    final model = ConnectionFormModel(existing: existing);
    addTearDown(model.dispose);
    model.password.text = 'new-pw';

    final updated = model.buildConfig();

    // Password changed.
    expect(updated.credential, isA<PlainCredential>());
    expect((updated.credential as PlainCredential).password, 'new-pw');
    // Identity preserved.
    expect(updated.id, 'c1');
    expect(updated.host, 'prod.example.com');
    // Per-connection bags survived.
    expect(updated.favoriteTables, {'public.users'});
    expect(updated.savedQueries, hasLength(1));
    expect(updated.savedQueries.first.name, 'recent signups');
    expect(updated.recentTables, ['public.users']);
    expect(updated.tableUseCounts, {'public.users': 7});
    expect(updated.columnWidths, {
      'public.users': {'id': 60, 'email': 240},
    });
    expect(updated.lastConnectedAt, DateTime(2026, 5, 1));
  });

  test('creating a new connection starts with empty bags', () {
    final model = ConnectionFormModel();
    addTearDown(model.dispose);
    model.host.text = 'localhost';
    model.port.text = '5432';
    model.database.text = 'app';
    model.username.text = 'me';
    model.password.text = 'pw';

    final created = model.buildConfig();

    expect(created.favoriteTables, isEmpty);
    expect(created.savedQueries, isEmpty);
    expect(created.recentTables, isEmpty);
    expect(created.columnWidths, isEmpty);
    expect(created.lastConnectedAt, isNull);
  });
}
