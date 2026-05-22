import 'dart:io';

import 'package:dbv/models/cell_edit.dart';
import 'package:dbv/models/connection_config.dart';
import 'package:dbv/models/db_object.dart';
import 'package:dbv/services/sqlite_service.dart';
import 'package:dbv/services/sqlite_table_repository.dart';
import 'package:dbv/services/table_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('buildSqliteEditStatements', () {
    final table = DbTable(
      oid: 1,
      schema: 'main',
      name: 'events',
      kind: DbRelationKind.table,
    );

    test('renders one UPDATE per rowid targeting the rowid column', () {
      final stmts = buildSqliteEditStatements(
        table,
        EditBatch(
          updatesByCtid: {
            '7': {
              'name': const CellLiteral('Alice'),
              'count': const CellLiteral('42'),
            },
          },
        ),
      );
      expect(stmts, hasLength(1));
      expect(stmts.first, contains('UPDATE "main"."events" SET'));
      expect(stmts.first, contains('"name" = \'Alice\''));
      expect(stmts.first, endsWith('WHERE rowid = 7'));
    });

    test('renders NULL for a null literal and doubles inner quotes', () {
      final stmts = buildSqliteEditStatements(
        table,
        EditBatch(
          updatesByCtid: {
            '1': {
              'note': const CellLiteral(null),
              'who': const CellLiteral("O'Brien"),
            },
          },
        ),
      );
      expect(stmts.first, contains('"note" = NULL'));
      expect(stmts.first, contains("'O''Brien'"));
    });

    test('renders DELETE per rowid', () {
      final stmts = buildSqliteEditStatements(
        table,
        EditBatch(deleteCtids: ['3', '4']),
      );
      expect(stmts, hasLength(2));
      expect(stmts.first, contains('DELETE FROM "main"."events"'));
      expect(stmts.first, endsWith('WHERE rowid = 3'));
    });

    test('omits DEFAULT columns from an INSERT so the row gets a fresh key', () {
      final stmts = buildSqliteEditStatements(
        table,
        EditBatch(
          inserts: [
            PendingInsert(
              values: {
                'id': const CellDefault(),
                'name': const CellLiteral('Alice'),
              },
            ),
          ],
        ),
      );
      expect(stmts.single, contains('INSERT INTO "main"."events" ("name")'));
      expect(stmts.single, contains("VALUES ('Alice')"));
      expect(stmts.single, isNot(contains('DEFAULT')));
    });

    test('all-DEFAULT INSERT falls back to DEFAULT VALUES', () {
      final stmts = buildSqliteEditStatements(
        table,
        EditBatch(
          inserts: [
            PendingInsert(values: {'id': const CellDefault()}),
          ],
        ),
      );
      expect(stmts.single, contains('DEFAULT VALUES'));
    });

    test('orders updates → deletes → inserts', () {
      final stmts = buildSqliteEditStatements(
        table,
        EditBatch(
          updatesByCtid: {
            '1': {'a': const CellLiteral('u')},
          },
          deleteCtids: ['2'],
          inserts: [
            PendingInsert(values: {'a': const CellLiteral('i')}),
          ],
        ),
      );
      expect(stmts[0], startsWith('UPDATE'));
      expect(stmts[1], startsWith('DELETE FROM'));
      expect(stmts[2], startsWith('INSERT INTO'));
    });
  });

  group('SqliteService against a real file', () {
    late Directory tmp;
    late SqliteService svc;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('dbv_sqlite_test');
      final dbPath = '${tmp.path}/library.db';
      final seed = sqlite3.open(dbPath);
      seed.execute('''
        CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
        CREATE TABLE books (
          id INTEGER PRIMARY KEY,
          title TEXT NOT NULL,
          author_id INTEGER REFERENCES authors(id)
        );
        CREATE INDEX idx_books_title ON books(title);
        INSERT INTO authors (id, name) VALUES (1, 'Le Guin'), (2, 'Borges');
        INSERT INTO books (id, title, author_id)
          VALUES (1, 'A Wizard of Earthsea', 1), (2, 'Ficciones', 2);
      ''');
      seed.dispose();

      svc = SqliteService(
        ConnectionConfig(
          id: 't',
          name: 'library',
          engine: DbEngine.sqlite,
          filePath: dbPath,
        ),
      );
      await svc.connect();
    });

    tearDown(() async {
      await svc.close();
      await tmp.delete(recursive: true);
    });

    test('connect fails clearly for a missing file', () async {
      final missing = SqliteService(
        ConnectionConfig(
          id: 'x',
          name: 'x',
          engine: DbEngine.sqlite,
          filePath: '${tmp.path}/does-not-exist.db',
        ),
      );
      expect(missing.connect(), throwsA(isA<Exception>()));
    });

    test('introspects schemas as a single main schema', () async {
      final schemas = await svc.introspector.loadSchemas();
      expect(schemas, hasLength(1));
      expect(schemas.single.name, 'main');
      expect(
        schemas.single.tables.map((t) => t.name),
        ['authors', 'books'],
      );
    });

    test('introspects columns with primary-key flags', () async {
      final schemas = await svc.introspector.loadSchemas();
      final books = schemas.single.tables.firstWhere((t) => t.name == 'books');
      final columns = await svc.introspector.loadAllColumns();
      final bookCols = columns[books.oid]!;
      expect(bookCols.map((c) => c.name), ['id', 'title', 'author_id']);
      expect(bookCols.firstWhere((c) => c.name == 'id').isPrimaryKey, isTrue);
      expect(
        bookCols.firstWhere((c) => c.name == 'title').nullable,
        isFalse,
      );
    });

    test('introspects the foreign key from books to authors', () async {
      final schemas = await svc.introspector.loadSchemas();
      final books = schemas.single.tables.firstWhere((t) => t.name == 'books');
      final fks = await svc.introspector.loadAllForeignKeys();
      final bookFks = fks[books.oid]!;
      expect(bookFks, hasLength(1));
      expect(bookFks.single.localColumn, 'author_id');
      expect(bookFks.single.refTable, 'authors');
      expect(bookFks.single.refColumn, 'id');
    });

    test('introspects the explicit index, skipping auto-indexes', () async {
      final schemas = await svc.introspector.loadSchemas();
      final books = schemas.single.tables.firstWhere((t) => t.name == 'books');
      final indexes = await svc.introspector.loadAllIndexes();
      expect(indexes[books.oid]!.map((i) => i.name), ['idx_books_title']);
    });

    test('fetchTablePage returns rowids for an editable table', () async {
      final schemas = await svc.introspector.loadSchemas();
      final books = schemas.single.tables.firstWhere((t) => t.name == 'books');
      final page = await svc.fetchTablePage(books, limit: 10, offset: 0);
      expect(page.rowIds, isNotNull);
      expect(page.rowIds, hasLength(2));
      expect(page.columns, ['id', 'title', 'author_id']);
      expect(page.rows, hasLength(2));
    });

    test('runQuery shapes a row result', () async {
      final result = await svc.runQuery('SELECT count(*) AS n FROM books');
      expect(result.isError, isFalse);
      expect(result.columns, ['n']);
      expect(result.rows.single.single, 2);
    });

    test('applyTableEdits commits an update by rowid', () async {
      final schemas = await svc.introspector.loadSchemas();
      final books = schemas.single.tables.firstWhere((t) => t.name == 'books');
      final affected = await svc.applyTableEdits(
        books,
        EditBatch(
          updatesByCtid: {
            '1': {'title': const CellLiteral('Earthsea')},
          },
        ),
      );
      expect(affected, 1);
      final check = await svc.runQuery('SELECT title FROM books WHERE id = 1');
      expect(check.rows.single.single, 'Earthsea');
    });

    test('applyTableEdits raises StaleRowException for a vanished row',
        () async {
      final schemas = await svc.introspector.loadSchemas();
      final books = schemas.single.tables.firstWhere((t) => t.name == 'books');
      expect(
        svc.applyTableEdits(
          books,
          EditBatch(
            updatesByCtid: {
              '999': {'title': const CellLiteral('ghost')},
            },
          ),
        ),
        throwsA(isA<StaleRowException>()),
      );
    });

    test('loadTableDdl returns the verbatim CREATE plus index DDL', () async {
      final schemas = await svc.introspector.loadSchemas();
      final books = schemas.single.tables.firstWhere((t) => t.name == 'books');
      final ddl = await svc.loadTableDdl(books);
      expect(ddl, contains('CREATE TABLE books'));
      expect(ddl, contains('CREATE INDEX idx_books_title'));
    });
  });
}
