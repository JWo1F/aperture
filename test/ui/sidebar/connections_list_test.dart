import 'package:aperture/models/connection_config.dart';
import 'package:aperture/services/atomic_json.dart';
import 'package:aperture/state/app_globals.dart';
import 'package:aperture/state/app_state.dart';
import 'package:aperture/state/app_store.dart';
import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/ui/sidebar/connections_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Writes nowhere: the list under test only cares about the in-memory
/// connections, and a real save would reach for the support directory.
class _NullJsonFile extends AtomicJsonFile {
  _NullJsonFile() : super('store.json');

  @override
  Future<void> save(Object data) async {}
}

void main() {
  late AppStore store;

  setUpAll(() {
    store = AppStore(file: _NullJsonFile());
    appState = AppState(store: store);
  });

  setUp(() => AppColors.setPalette(darkPalette));

  /// `const AllConnectionsList()` is how the sidebar mounts it, and
  /// Flutter's element-update path short-circuits on an identical widget
  /// reference — so the list has to hold its own store subscription.
  Widget harness() => MaterialApp(
    home: Scaffold(
      body: ListenableBuilder(
        listenable: appState.store,
        builder: (_, _) => const SizedBox(
          width: 260,
          height: 600,
          child: AllConnectionsList(),
        ),
      ),
    ),
  );

  testWidgets('a deleted connection leaves the saved list', (tester) async {
    store.addConnection(ConnectionConfig(id: 'a', name: 'alpha'));
    store.addConnection(ConnectionConfig(id: 'b', name: 'beta'));

    await tester.pumpWidget(harness());
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);

    store.removeConnection('a');
    await tester.pump();

    expect(find.text('alpha'), findsNothing);
    expect(find.text('beta'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
  });
}
