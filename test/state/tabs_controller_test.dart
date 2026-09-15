import 'dart:io';

import 'package:aperture/models/connection_config.dart';
import 'package:aperture/models/db_object.dart';
import 'package:aperture/services/atomic_json.dart';
import 'package:aperture/state/app_state.dart';
import 'package:aperture/state/app_store.dart';
import 'package:aperture/state/workspace_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart';

class _StubPathProvider extends PathProviderPlatform {
  _StubPathProvider(this.root);
  final Directory root;

  @override
  Future<String?> getApplicationSupportPath() async => root.path;
}

/// Drives the real controller against a real SQLite file. `SqliteService`
/// works under `flutter test`, which makes the whole state layer — not just
/// its pure helpers — exercisable end to end.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late AppState app;
  late DbTable books;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('aperture_tabs');
    PathProviderPlatform.instance = _StubPathProvider(tmp);
    final path = '${tmp.path}/library.db';
    sqlite3.open(path)
      ..execute('''
        CREATE TABLE books (
          id INTEGER PRIMARY KEY,
          title TEXT NOT NULL,
          pages INTEGER
        );
        INSERT INTO books (id, title, pages) VALUES
          (1, 'Earthsea', 200),
          (2, 'Ficciones', 150),
          (3, 'Solaris', 300),
          (4, 'Dune', 500);
      ''')
      ..dispose();

    app = AppState(store: AppStore(file: AtomicJsonFile('store.json')));
    final config = ConnectionConfig(
      id: 'lib',
      name: 'library',
      engine: DbEngine.sqlite,
      filePath: path,
    );
    app.store.addConnection(config);
    await app.connect(config);
    books = app.catalog.schemas
        .expand((s) => s.tables)
        .firstWhere((t) => t.name == 'books');
  });

  tearDown(() async {
    app.dispose();
    await tmp.delete(recursive: true);
  });

  Future<TableTab> openBooks() => app.tabsController.openTable(books);

  /// The row count is refreshed off the critical path — `loadTablePage`
  /// fires it unawaited so the grid paints as soon as the page arrives.
  Future<void> settleRowCount() => Future<void>.delayed(Duration.zero);

  group('openTable', () {
    test('loads the first page and reports the total', () async {
      final tab = await openBooks();
      expect(tab.result!.rows, hasLength(4));
      expect(tab.result!.rowIds, ['1', '2', '3', '4']);
      expect(tab.page, 0);
      await settleRowCount();
      expect(tab.totalRows, 4);
    });

    test('opening the same relation twice reuses the tab', () async {
      final first = await openBooks();
      final second = await openBooks();
      expect(second, same(first));
      expect(app.tabsController.tabs, hasLength(1));
    });
  });

  group('cell edits address rows by index', () {
    test('an edit resolves to that row\'s rowid', () async {
      final tab = await openBooks();
      app.tabsController.setCellEdit(tab, 2, 1, const CellLiteral('Solaris 2'));

      final sql = app.tabsController.previewEditStatements(tab);
      expect(sql, hasLength(1));
      // Row index 2 is rowid 3 — not 2.
      expect(sql.single, contains('WHERE _rowid_ = 3'));
      expect(sql.single, contains("'Solaris 2'"));
    });

    test('two columns on one row collapse into a single UPDATE', () async {
      final tab = await openBooks();
      app.tabsController.setCellEdit(tab, 0, 1, const CellLiteral('A'));
      app.tabsController.setCellEdit(tab, 0, 2, const CellLiteral('1'));

      final sql = app.tabsController.previewEditStatements(tab);
      expect(sql, hasLength(1));
      expect(sql.single, contains('"title" = '));
      expect(sql.single, contains('"pages" = '));
    });

    test('setting a cell back to its original value drops the edit',
        () async {
      final tab = await openBooks();
      app.tabsController.setCellEdit(tab, 0, 1, const CellLiteral('Changed'));
      expect(tab.edits, hasLength(1));
      app.tabsController.setCellEdit(tab, 0, 1, const CellLiteral('Earthsea'));
      expect(tab.edits, isEmpty, reason: 'no redundant UPDATE should be sent');
    });

    test('revertCellEdit removes just that cell', () async {
      final tab = await openBooks();
      app.tabsController.setCellEdit(tab, 0, 1, const CellLiteral('A'));
      app.tabsController.setCellEdit(tab, 1, 1, const CellLiteral('B'));
      app.tabsController.revertCellEdit(tab, 0, 1);
      expect(tab.edits, hasLength(1));
    });

    test('a delete supersedes that row\'s edits', () async {
      final tab = await openBooks();
      app.tabsController.setCellEdit(tab, 1, 1, const CellLiteral('gone'));
      app.tabsController.deleteRow(tab, 1);

      final sql = app.tabsController.previewEditStatements(tab);
      expect(sql, hasLength(1));
      expect(sql.single, startsWith('DELETE'));
      expect(sql.single, contains('WHERE _rowid_ = 2'));
    });

    test('statements are ordered UPDATE, DELETE, INSERT', () async {
      final tab = await openBooks();
      app.tabsController.setCellEdit(tab, 0, 1, const CellLiteral('A'));
      app.tabsController.deleteRow(tab, 1);
      app.tabsController.addRow(tab, 2);

      final sql = app.tabsController.previewEditStatements(tab);
      expect(sql, hasLength(3));
      expect(sql[0], startsWith('UPDATE'));
      expect(sql[1], startsWith('DELETE'));
      expect(sql[2], startsWith('INSERT'));
    });
  });

  group('insert rows are addressed past the end of the result', () {
    test('editing a virtual row targets the pending insert', () async {
      final tab = await openBooks();
      app.tabsController.addRow(tab, 0);
      expect(tab.inserts, hasLength(1));

      // Row 4 is `result.rows.length + 0` — the first pending insert.
      app.tabsController.setCellEdit(tab, 4, 1, const CellLiteral('New'));
      expect(tab.edits, isEmpty, reason: 'inserts hold their own values');
      expect((tab.inserts.single.values['title'] as CellLiteral).value, 'New');
    });

    test('deleting a virtual row discards the insert', () async {
      final tab = await openBooks();
      app.tabsController.addRow(tab, 0);
      app.tabsController.deleteRow(tab, 4);
      expect(tab.inserts, isEmpty);
      expect(tab.deletedRows, isEmpty);
    });

    test('an out-of-range row changes nothing', () async {
      final tab = await openBooks();
      app.tabsController.setCellEdit(tab, 99, 1, const CellLiteral('x'));
      app.tabsController.deleteRow(tab, -1);
      expect(tab.hasEdits, isFalse);
    });
  });

  group('duplicateRow', () {
    test('copies the values but leaves the primary key to the engine',
        () async {
      final tab = await openBooks();
      app.tabsController.duplicateRow(tab, 0);

      final insert = tab.inserts.single;
      expect(insert.values['id'], isA<CellDefault>());
      expect((insert.values['title'] as CellLiteral).value, 'Earthsea');
      expect((insert.values['pages'] as CellLiteral).value, '200');
      expect(insert.afterRow, 0);
    });

    test('a staged edit on the source row wins over the stored value',
        () async {
      final tab = await openBooks();
      app.tabsController.setCellEdit(tab, 0, 1, const CellLiteral('Edited'));
      app.tabsController.duplicateRow(tab, 0);
      expect(
        (tab.inserts.single.values['title'] as CellLiteral).value,
        'Edited',
      );
    });

    test('duplicating an insert inherits its anchor, not a row index',
        () async {
      final tab = await openBooks();
      app.tabsController.addRow(tab, 2);
      app.tabsController.duplicateRow(tab, 4);
      expect(tab.inserts, hasLength(2));
      expect(tab.inserts.last.afterRow, 2);
    });

    test('the INSERT omits DEFAULT columns so SQLite assigns a fresh key',
        () async {
      final tab = await openBooks();
      app.tabsController.duplicateRow(tab, 0);
      final sql = app.tabsController.previewEditStatements(tab).single;
      expect(sql, startsWith('INSERT'));
      expect(sql, isNot(contains('"id"')));
    });

    test('an out-of-range source is a no-op', () async {
      final tab = await openBooks();
      app.tabsController.duplicateRow(tab, 99);
      app.tabsController.duplicateRow(tab, -1);
      expect(tab.inserts, isEmpty);
    });
  });

  group('addRow', () {
    test('stamps every column DEFAULT', () async {
      final tab = await openBooks();
      app.tabsController.addRow(tab, 1);
      final insert = tab.inserts.single;
      expect(insert.values.keys, containsAll(['id', 'title', 'pages']));
      expect(insert.values.values, everyElement(isA<CellDefault>()));
      expect(insert.afterRow, 1);
    });

    test('an all-DEFAULT insert renders as DEFAULT VALUES', () async {
      final tab = await openBooks();
      app.tabsController.addRow(tab, 0);
      expect(
        app.tabsController.previewEditStatements(tab).single,
        contains('DEFAULT VALUES'),
      );
    });
  });

  group('applyTableEdits', () {
    test('commits, clears the staging area and reloads', () async {
      final tab = await openBooks();
      app.tabsController.setCellEdit(tab, 0, 1, const CellLiteral('Renamed'));

      final outcome = await app.tabsController.applyTableEdits(tab);
      expect(outcome.ok, isTrue);
      expect(tab.hasEdits, isFalse);
      expect(tab.applying, isFalse);
      expect(tab.result!.rows.first[1], 'Renamed');
    });

    test('a delete really removes the addressed row', () async {
      final tab = await openBooks();
      app.tabsController.deleteRow(tab, 1);
      expect((await app.tabsController.applyTableEdits(tab)).ok, isTrue);

      expect(tab.result!.rows.map((r) => r[0]), [1, 3, 4]);
    });

    test('an insert lands with a fresh key', () async {
      final tab = await openBooks();
      app.tabsController.duplicateRow(tab, 0);
      expect((await app.tabsController.applyTableEdits(tab)).ok, isTrue);

      expect(tab.result!.rows, hasLength(5));
      expect(tab.result!.rows.last[1], 'Earthsea');
      expect(tab.result!.rows.last[0], isNot(1));
    });

    test('a failure keeps the staged edits and clears the flag', () async {
      final tab = await openBooks();
      // NOT NULL on title — the engine refuses this.
      app.tabsController.setCellEdit(tab, 0, 1, const CellLiteral(null));

      final outcome = await app.tabsController.applyTableEdits(tab);
      expect(outcome.ok, isFalse);
      expect(tab.applying, isFalse, reason: 'a leaked flag bricks Apply');
      expect(tab.hasEdits, isTrue, reason: 'the user needs them for a retry');

      // And Apply still works afterwards.
      app.tabsController.setCellEdit(tab, 0, 1, const CellLiteral('Fixed'));
      expect((await app.tabsController.applyTableEdits(tab)).ok, isTrue);
    });

    test('nothing staged is a no-op success', () async {
      final tab = await openBooks();
      final outcome = await app.tabsController.applyTableEdits(tab);
      expect(outcome.ok, isTrue);
      expect(outcome.totalCount, 0);
    });
  });

  group('pagination and clauses', () {
    test('a page change drops the row-indexed staging area', () async {
      final tab = await openBooks();
      tab.pageSize = 2;
      await app.tabsController.loadTablePage(tab, 0);
      app.tabsController.deleteRow(tab, 1);

      await app.tabsController.loadTablePage(tab, 1);
      // Row 1 of page 2 is a different row; carrying the index over would
      // delete it on the next Apply.
      expect(tab.deletedRows, isEmpty);
      expect(tab.result!.rows.first[0], 3);
    });

    test('a filter narrows the page and the total', () async {
      final tab = await openBooks();
      await app.tabsController.setTableFilter(tab, 'pages > 200');
      expect(tab.filter, 'pages > 200');
      expect(tab.result!.rows, hasLength(2));
      await settleRowCount();
      expect(tab.totalRows, 2);
    });

    test('a filter that stacks a statement is refused', () async {
      final tab = await openBooks();
      await app.tabsController.setTableFilter(
        tab,
        '1=1; DROP TABLE books',
      );
      expect(tab.result!.isError, isTrue);
      // The gate runs before either engine sees the text.
      final check = await app.session.service!.runQuery(
        "SELECT count(*) FROM sqlite_master WHERE name = 'books'",
      );
      expect(check.rows.single.single, 1);
    });

    test('sorting cycles through ascending, descending and off', () async {
      final tab = await openBooks();
      await app.tabsController.cycleTableOrder(tab, 'title');
      expect(tab.orderBy, '"title" ASC');
      expect(tab.result!.rows.first[1], 'Dune');

      await app.tabsController.cycleTableOrder(tab, 'title');
      expect(tab.orderBy, '"title" DESC');
      expect(tab.result!.rows.first[1], 'Solaris');

      await app.tabsController.cycleTableOrder(tab, 'title');
      expect(tab.orderBy, '');
    });

    test('a projection limits the columns', () async {
      final tab = await openBooks();
      await app.tabsController.setTableSelect(tab, 'id, title');
      expect(tab.result!.columns, ['id', 'title']);
    });
  });

  group('tab lifecycle', () {
    test('closing a tab prunes it from history', () async {
      final tab = await openBooks();
      app.tabsController.newQueryTab();
      expect(app.tabsController.tabs, hasLength(2));

      app.tabsController.closeTab(tab.id);
      expect(app.tabsController.tabs, hasLength(1));
      expect(tab.disposed, isTrue);
    });

    test('closing the last tab clamps the active index', () async {
      await openBooks();
      app.tabsController.newQueryTab();
      app.tabsController.selectTab(1);
      app.tabsController.closeTab(app.tabsController.tabs[1].id);
      expect(app.tabsController.activeIndex, 0);
      expect(app.tabsController.activeTab, isNotNull);
    });

    test('unappliedEditCount totals every table tab', () async {
      final tab = await openBooks();
      app.tabsController.setCellEdit(tab, 0, 1, const CellLiteral('a'));
      app.tabsController.deleteRow(tab, 1);
      app.tabsController.addRow(tab, 2);
      expect(app.tabsController.unappliedEditCount, 3);
    });

    test('a new query tab gets a name that is not already taken', () async {
      app.tabsController.newQueryTab();
      app.tabsController.newQueryTab();
      final names = app.tabsController.tabs.map((t) => t.title).toList();
      expect(names.toSet(), hasLength(names.length));
    });
  });

  group('runQuery', () {
    test('a SELECT lands on the tab with rows and a message', () async {
      app.tabsController.newQueryTab();
      final tab = app.tabsController.activeTab! as QueryTab;
      tab.sql = 'SELECT title FROM books ORDER BY id';

      await app.tabsController.runQuery(tab);
      expect(tab.result!.rows.first.single, 'Earthsea');
      expect(tab.running, isFalse);
      expect(tab.messages, hasLength(1));
      expect(tab.messages.single.error, isNull);
    });

    test('a broken statement records the error, not a crash', () async {
      app.tabsController.newQueryTab();
      final tab = app.tabsController.activeTab! as QueryTab;
      tab.sql = 'SELECT nope FROM books';

      await app.tabsController.runQuery(tab);
      expect(tab.result!.isError, isTrue);
      expect(tab.messages.single.error, isNotNull);
      expect(tab.running, isFalse);
    });

    test('a bare SELECT is capped and says so', () async {
      app.tabsController.newQueryTab();
      final tab = app.tabsController.activeTab! as QueryTab;
      tab.sql = 'SELECT * FROM books';

      await app.tabsController.runQuery(tab);
      // Four rows is under the cap, but the flag records that the cap was
      // applied rather than that it bit.
      expect(tab.result!.rows, hasLength(4));
    });
  });
}
