import 'package:dbv/models/db_catalog.dart';
import 'package:dbv/models/db_object.dart';
import 'package:dbv/services/sql_complete.dart';
import 'package:dbv/ui/widgets/code_editor.dart';
import 'package:flutter_test/flutter_test.dart';

DbTable _t(int oid, String schema, String name) =>
    DbTable(oid: oid, schema: schema, name: name, kind: DbRelationKind.table);

DbColumn _c(String name, String type, {bool pk = false}) => DbColumn(
  name: name,
  dataType: type,
  nullable: !pk,
  isPrimaryKey: pk,
  hasDefault: false,
  ordinal: 1,
);

DatabaseCatalog _catalog(
  List<DbTable> tables, {
  Map<int, List<DbColumn>> columns = const {},
}) {
  final byOid = {for (final t in tables) t.oid: t};
  return DatabaseCatalog.empty.copyWith(
    schemas: const [],
    relationsByOid: byOid,
    columnsByOid: columns,
    phases: {CatalogPhase.schemas, CatalogPhase.columns},
  );
}

SuggestRequest _req(
  String text, {
  int? cursor,
  bool manualTrigger = false,
}) {
  final at = cursor ?? text.length;
  var ts = at;
  bool isWord(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F;
  while (ts > 0 && isWord(text.codeUnitAt(ts - 1))) {
    ts--;
  }
  return SuggestRequest(
    text: text,
    cursor: at,
    token: text.substring(ts, at),
    tokenStart: ts,
    manualTrigger: manualTrigger,
  );
}

void main() {
  group('parseScope', () {
    test('picks up FROM <table>', () {
      final cat = _catalog([_t(1, 'public', 'users')]);
      final scope = parseScope('SELECT * FROM users WHERE id = 1', cat);
      expect(scope.tables.map((t) => t.name), ['users']);
      expect(scope.aliases.keys, contains('users'));
    });

    test('picks up FROM schema.table', () {
      final cat = _catalog([_t(2, 'app', 'orders')]);
      final scope = parseScope('SELECT * FROM app.orders', cat);
      expect(scope.tables.single.qualifiedKey, 'app.orders');
    });

    test('captures alias and ignores trailing clause keywords', () {
      final cat = _catalog([_t(1, 'public', 'users')]);
      final scope =
          parseScope('SELECT u.id FROM users u WHERE u.active', cat);
      expect(scope.aliases.containsKey('u'), isTrue);
      expect(scope.aliases.containsKey('where'), isFalse);
    });

    test('captures both sides of a JOIN', () {
      final cat = _catalog([
        _t(1, 'public', 'users'),
        _t(2, 'public', 'orders'),
      ]);
      final scope = parseScope(
        'SELECT * FROM users JOIN orders ON users.id = orders.user_id',
        cat,
      );
      expect(scope.tables.map((t) => t.name), ['users', 'orders']);
    });

    test('unknown table is skipped', () {
      final cat = _catalog([_t(1, 'public', 'users')]);
      final scope = parseScope('SELECT * FROM nope', cat);
      expect(scope.tables, isEmpty);
    });
  });

  group('previousWord', () {
    test('returns lowercased word immediately before tokenStart', () {
      expect(previousWord('SELECT * FROM u', 14), 'from');
      expect(previousWord('select * from u', 14), 'from');
    });

    test('returns empty when nothing precedes the token', () {
      expect(previousWord('users', 0), '');
    });

    test('skips whitespace between token and prior word', () {
      expect(previousWord('JOIN    orders', 8), 'join');
    });
  });

  group('detectClause', () {
    test('empty text is statementStart', () {
      expect(detectClause('', 0), SqlClause.statementStart);
    });

    test('after SELECT is selectList', () {
      expect(detectClause('SELECT id', 9), SqlClause.selectList);
    });

    test('after FROM is from', () {
      expect(detectClause('SELECT * FROM u', 15), SqlClause.from);
    });

    test('after WHERE is where', () {
      expect(detectClause('SELECT * FROM t WHERE x', 23), SqlClause.where);
    });

    test('after ORDER BY is orderBy, not the bare BY', () {
      expect(
        detectClause('SELECT * FROM t ORDER BY x', 26),
        SqlClause.orderBy,
      );
    });

    test('clause keywords inside string literals are ignored', () {
      expect(
        detectClause("SELECT 'WHERE x' FROM t", 23),
        SqlClause.from,
      );
    });

    test('clause keywords inside line comments are ignored', () {
      expect(
        detectClause('SELECT x -- WHERE\n FROM t', 25),
        SqlClause.from,
      );
    });
  });

  group('qualifierBefore', () {
    test('null when no dot precedes the token', () {
      expect(qualifierBefore('SELECT u', 7), isNull);
    });

    test('returns the bare identifier before a dot', () {
      expect(qualifierBefore('SELECT u.i', 9), 'u');
    });

    test('null when only a dot but no preceding identifier', () {
      expect(qualifierBefore('SELECT .i', 8), isNull);
    });
  });

  group('isInsideStringOrComment', () {
    test('false outside quotes', () {
      expect(isInsideStringOrComment("SELECT 'x' FROM t", 12), isFalse);
    });

    test('true inside a single-quoted literal', () {
      expect(isInsideStringOrComment("SELECT 'abc", 10), isTrue);
    });

    test('escaped quote does not close the string', () {
      expect(isInsideStringOrComment("SELECT 'a''b", 11), isTrue);
    });

    test('true inside a -- line comment', () {
      expect(isInsideStringOrComment('SELECT 1 -- note', 14), isTrue);
    });

    test('true inside a /* … */ block comment', () {
      expect(isInsideStringOrComment('SELECT /* x', 10), isTrue);
    });
  });

  group('completeQueryEditor', () {
    test('returns only columns of the qualified table on dot completion', () {
      final users = _t(1, 'public', 'users');
      final orders = _t(2, 'public', 'orders');
      final cat = _catalog(
        [users, orders],
        columns: {
          1: [_c('id', 'int', pk: true), _c('email', 'text')],
          2: [_c('id', 'int', pk: true), _c('total', 'numeric')],
        },
      );
      const text = 'SELECT * FROM users u WHERE u.';
      final out = completeQueryEditor(
        req: _req(text, manualTrigger: true),
        catalog: cat,
        stmtText: text,
      );
      expect(out.map((s) => s.label).toSet(), {'id', 'email'});
      // No keywords in dot completion.
      expect(out.every((s) => s.kind == SuggestionKind.column), isTrue);
    });

    test('case-sensitive prefix ranks ahead of case-insensitive prefix', () {
      final users = _t(1, 'public', 'users');
      final cat = _catalog(
        [users],
        columns: {1: [_c('Status', 'text'), _c('status_at', 'timestamp')]},
      );
      const text = 'SELECT s FROM users';
      final out = completeQueryEditor(
        req: SuggestRequest(
          text: text,
          cursor: 8,
          token: 's',
          tokenStart: 7,
        ),
        catalog: cat,
        stmtText: text,
      );
      expect(out.first.label, 'status_at');
    });

    test('returns nothing inside a string literal', () {
      final users = _t(1, 'public', 'users');
      final cat = _catalog([users], columns: {1: [_c('id', 'int')]});
      const text = "SELECT 'i FROM users";
      final out = completeQueryEditor(
        req: SuggestRequest(
          text: text,
          cursor: 9,
          token: 'i',
          tokenStart: 8,
        ),
        catalog: cat,
        stmtText: text,
      );
      expect(out, isEmpty);
    });

    test('caps result list', () {
      final users = _t(1, 'public', 'lots');
      final cat = _catalog(
        [users],
        columns: {
          1: [for (var i = 0; i < 80; i++) _c('col_$i', 'int')],
        },
      );
      const text = 'SELECT c FROM lots';
      final out = completeQueryEditor(
        req: SuggestRequest(
          text: text,
          cursor: 8,
          token: 'c',
          tokenStart: 7,
        ),
        catalog: cat,
        stmtText: text,
      );
      expect(out.length, lessThanOrEqualTo(30));
    });

    test('FROM context offers tables but no FK join templates', () {
      final users = _t(1, 'public', 'users');
      final orders = _t(2, 'public', 'orders');
      final cat = _catalog(
        [users, orders],
        columns: {
          1: [_c('id', 'int', pk: true)],
          2: [_c('user_id', 'int')],
        },
      ).copyWith(
        foreignKeysByOid: {
          2: [
            DbForeignKey(
              constraintName: 'orders_user_fk',
              localColumns: ['user_id'],
              refSchema: 'public',
              refTable: 'users',
              refTableOid: 1,
              refColumns: ['id'],
            ),
          ],
        },
        phases: {
          CatalogPhase.schemas,
          CatalogPhase.columns,
          CatalogPhase.foreignKeys,
        },
      );
      const text = 'SELECT * FROM ';
      final out = completeQueryEditor(
        req: _req(text, manualTrigger: true),
        catalog: cat,
        stmtText: text,
      );
      expect(
        out.every((s) => s.kind != SuggestionKind.snippet),
        isTrue,
        reason: 'no `users ON …` join template should leak in after FROM',
      );
      expect(out.any((s) => s.label == 'users'), isTrue);
      expect(out.any((s) => s.label == 'orders'), isTrue);
    });

    test('JOIN context offers FK templates plus bare tables', () {
      final users = _t(1, 'public', 'users');
      final orders = _t(2, 'public', 'orders');
      final cat = _catalog(
        [users, orders],
        columns: {
          1: [_c('id', 'int', pk: true)],
          2: [_c('user_id', 'int')],
        },
      ).copyWith(
        foreignKeysByOid: {
          2: [
            DbForeignKey(
              constraintName: 'orders_user_fk',
              localColumns: ['user_id'],
              refSchema: 'public',
              refTable: 'users',
              refTableOid: 1,
              refColumns: ['id'],
            ),
          ],
        },
        phases: {
          CatalogPhase.schemas,
          CatalogPhase.columns,
          CatalogPhase.foreignKeys,
        },
      );
      const text = 'SELECT * FROM users JOIN ';
      final out = completeQueryEditor(
        req: _req(text, manualTrigger: true),
        catalog: cat,
        stmtText: text,
      );
      expect(
        out.any((s) => s.kind == SuggestionKind.snippet),
        isTrue,
        reason: 'should include at least one FK-derived join template',
      );
      expect(out.any((s) => s.kind == SuggestionKind.table), isTrue);
    });

    test('soft-trigger: empty token after JOIN+space pops tables', () {
      final users = _t(1, 'public', 'users');
      final orders = _t(2, 'public', 'orders');
      final cat = _catalog(
        [users, orders],
        columns: {
          1: [_c('id', 'int', pk: true)],
          2: [_c('user_id', 'int')],
        },
      );
      const text = 'SELECT * FROM users JOIN ';
      final out = completeQueryEditor(
        req: SuggestRequest(
          text: text,
          cursor: text.length,
          token: '',
          tokenStart: text.length,
        ),
        catalog: cat,
        stmtText: text,
      );
      expect(out.any((s) => s.label == 'orders'), isTrue);
      expect(out.any((s) => s.label == 'users'), isTrue);
    });

    test('soft-trigger: empty token mid-whitespace does NOT pop', () {
      final users = _t(1, 'public', 'users');
      final cat = _catalog([users], columns: {1: [_c('id', 'int')]});
      const text = 'SELECT * FROM users WHERE id = 1 ';
      final out = completeQueryEditor(
        req: SuggestRequest(
          text: text,
          cursor: text.length,
          token: '',
          tokenStart: text.length,
        ),
        catalog: cat,
        stmtText: text,
      );
      expect(out, isEmpty);
    });

    test('soft-trigger: SELECT+space lists `*` first, ahead of keywords', () {
      final users = _t(1, 'public', 'users');
      final cat = _catalog([users], columns: {1: [_c('id', 'int')]});
      const text = 'SELECT ';
      final out = completeQueryEditor(
        req: SuggestRequest(
          text: text,
          cursor: text.length,
          token: '',
          tokenStart: text.length,
        ),
        catalog: cat,
        stmtText: text,
      );
      expect(out, isNotEmpty);
      expect(out.first.label, '*');
      expect(out.any((s) => s.label == 'DISTINCT'), isTrue);
    });

    test('schema.table.col qualifier returns only that table\'s columns', () {
      final users = _t(1, 'app', 'users');
      final orders = _t(2, 'app', 'orders');
      final cat = _catalog(
        [users, orders],
        columns: {
          1: [_c('id', 'int', pk: true), _c('email', 'text')],
          2: [_c('id', 'int', pk: true), _c('total', 'numeric')],
        },
      );
      const text = 'SELECT * FROM app.users WHERE app.users.';
      final out = completeQueryEditor(
        req: _req(text, manualTrigger: true),
        catalog: cat,
        stmtText: text,
      );
      expect(out.map((s) => s.label).toSet(), {'id', 'email'});
    });

    test('schema. alone returns tables in that schema', () {
      final users = _t(1, 'app', 'users');
      final orders = _t(2, 'app', 'orders');
      final inv = _t(3, 'public', 'invoices');
      final cat = _catalog([users, orders, inv]);
      const text = 'SELECT * FROM app.';
      final out = completeQueryEditor(
        req: _req(text, manualTrigger: true),
        catalog: cat,
        stmtText: text,
      );
      expect(out.map((s) => s.label).toSet(), {'users', 'orders'});
      expect(out.every((s) => s.kind == SuggestionKind.table), isTrue);
    });

    test('typing alias-dot auto-triggers without manual trigger', () {
      final users = _t(1, 'public', 'users');
      final cat = _catalog(
        [users],
        columns: {1: [_c('id', 'int', pk: true), _c('email', 'text')]},
      );
      const text = 'SELECT u. FROM users u';
      final out = completeQueryEditor(
        req: SuggestRequest(
          text: text,
          cursor: 9,
          token: '',
          tokenStart: 9,
        ),
        catalog: cat,
        stmtText: text,
      );
      expect(out.map((s) => s.label).toSet(), {'id', 'email'});
    });

    test('typing schema-dot auto-triggers without manual trigger', () {
      final users = _t(1, 'app', 'users');
      final cat = _catalog([users]);
      const text = 'SELECT * FROM app.';
      final out = completeQueryEditor(
        req: SuggestRequest(
          text: text,
          cursor: text.length,
          token: '',
          tokenStart: text.length,
        ),
        catalog: cat,
        stmtText: text,
      );
      expect(out.any((s) => s.label == 'users'), isTrue);
    });

    test('alias.col resolves columns of the aliased table', () {
      final users = _t(1, 'public', 'users');
      final orders = _t(2, 'public', 'orders');
      final cat = _catalog(
        [users, orders],
        columns: {
          1: [_c('id', 'int', pk: true), _c('email', 'text')],
          2: [_c('id', 'int', pk: true), _c('total', 'numeric')],
        },
      );
      const text = 'SELECT u. FROM users u JOIN orders o ON u.id = o.user_id';
      final out = completeQueryEditor(
        req: SuggestRequest(
          text: text,
          cursor: 9,
          token: '',
          tokenStart: 9,
          manualTrigger: true,
        ),
        catalog: cat,
        stmtText: text,
      );
      expect(out.map((s) => s.label).toSet(), {'id', 'email'});
    });

    test('after SELECT * space, FROM is first, * is not re-suggested', () {
      final users = _t(1, 'public', 'users');
      final cat = _catalog([users], columns: {1: [_c('id', 'int')]});
      const text = 'SELECT * ';
      final out = completeQueryEditor(
        req: SuggestRequest(
          text: text,
          cursor: text.length,
          token: '',
          tokenStart: text.length,
          manualTrigger: true,
        ),
        catalog: cat,
        stmtText: text,
      );
      expect(out.first.label, 'FROM');
      expect(out.any((s) => s.label == '*'), isFalse);
    });

    test('after SELECT id space, FROM is first, * is not re-suggested', () {
      final users = _t(1, 'public', 'users');
      final cat = _catalog([users], columns: {1: [_c('id', 'int')]});
      const text = 'SELECT id ';
      final out = completeQueryEditor(
        req: SuggestRequest(
          text: text,
          cursor: text.length,
          token: '',
          tokenStart: text.length,
          manualTrigger: true,
        ),
        catalog: cat,
        stmtText: text,
      );
      expect(out.first.label, 'FROM');
      expect(out.any((s) => s.label == '*'), isFalse);
    });

    test('after FROM <table> space, suggests clauses not columns', () {
      final users = _t(1, 'public', 'users');
      final cat = _catalog(
        [users],
        columns: {1: [_c('id', 'int', pk: true), _c('email', 'text')]},
      );
      const text = 'SELECT * FROM users ';
      final out = completeQueryEditor(
        req: SuggestRequest(
          text: text,
          cursor: text.length,
          token: '',
          tokenStart: text.length,
          manualTrigger: true,
        ),
        catalog: cat,
        stmtText: text,
      );
      expect(out.any((s) => s.label == 'WHERE'), isTrue);
      expect(out.any((s) => s.label == 'ORDER BY'), isTrue);
      expect(
        out.every((s) => s.kind != SuggestionKind.column),
        isTrue,
        reason: 'columns shouldn\'t leak into a FROM-continuation slot',
      );
    });

    test('empty token in non-trigger whitespace returns nothing', () {
      final users = _t(1, 'public', 'users');
      final cat = _catalog([users], columns: {1: [_c('id', 'int')]});
      const text = 'SELECT id  FROM users';
      // Cursor sits in the gap between `id` and `FROM`. The prior word
      // is the identifier `id`, not a clause keyword — no soft trigger.
      final out = completeQueryEditor(
        req: const SuggestRequest(
          text: text,
          cursor: 10,
          token: '',
          tokenStart: 10,
        ),
        catalog: cat,
        stmtText: text,
      );
      expect(out, isEmpty);
    });
  });

  group('DDL completion', () {
    final cat = _catalog(
      [_t(1, 'public', 'users'), _t(2, 'public', 'orders')],
      columns: {
        1: [_c('id', 'int', pk: true), _c('email', 'text')],
        2: [_c('id', 'int', pk: true), _c('user_id', 'int')],
      },
    );

    List<CodeSuggestion> run(String text) => completeQueryEditor(
      req: _req(text, manualTrigger: true),
      catalog: cat,
      stmtText: text,
    );

    test('CREATE offers object kinds', () {
      final out = run('CREATE ');
      expect(out.map((s) => s.label), containsAll(['TABLE', 'INDEX', 'VIEW']));
    });

    test('CREATE TABLE column slot offers data types', () {
      final out = run('CREATE TABLE widgets (id ');
      expect(out.map((s) => s.label), containsAll(['integer', 'text']));
    });

    test('CREATE TABLE after a type offers column constraints', () {
      final out = run('CREATE TABLE widgets (id integer ');
      expect(
        out.map((s) => s.label),
        containsAll(['PRIMARY KEY', 'NOT NULL']),
      );
    });

    test('ALTER TABLE offers table actions', () {
      final out = run('ALTER TABLE users ');
      expect(
        out.map((s) => s.label),
        containsAll(['ADD COLUMN', 'DROP COLUMN']),
      );
    });

    test('ALTER TABLE DROP COLUMN offers the target table columns', () {
      final out = run('ALTER TABLE users DROP COLUMN ');
      expect(out.map((s) => s.label).toSet(), {'id', 'email'});
    });

    test('ALTER TABLE ALTER COLUMN offers column actions', () {
      final out = run('ALTER TABLE users ALTER COLUMN email ');
      expect(
        out.map((s) => s.label),
        containsAll(['SET DEFAULT', 'SET NOT NULL']),
      );
    });

    test('ALTER TABLE ADD COLUMN offers data types after the name', () {
      final out = run('ALTER TABLE users ADD COLUMN flag ');
      expect(out.map((s) => s.label), containsAll(['boolean', 'integer']));
    });

    test('ALTER TABLE ALTER COLUMN TYPE offers data types', () {
      final out = run('ALTER TABLE users ALTER COLUMN email TYPE var');
      expect(out.first.label, 'varchar');
    });

    test('DROP TABLE offers table names', () {
      final out = run('DROP TABLE ');
      expect(out.map((s) => s.label), containsAll(['users', 'orders']));
    });

    test('TRUNCATE offers TABLE and table names', () {
      final out = run('TRUNCATE ');
      expect(out.map((s) => s.label), containsAll(['TABLE', 'users']));
    });

    test('CREATE INDEX column list offers the target table columns', () {
      final out = run('CREATE INDEX idx ON users (');
      expect(out.map((s) => s.label), containsAll(['id', 'email']));
    });

    test('CREATE VIEW … AS SELECT delegates to the SELECT completer', () {
      final out = run('CREATE VIEW v AS SELECT ');
      expect(out.first.label, '*');
    });
  });
}
