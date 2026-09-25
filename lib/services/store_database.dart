import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/connection_config.dart';
import '../models/query_message.dart';
import '../models/saved_query.dart';

/// The passphrase did not open the store.
class WrongPassphraseException implements Exception {
  const WrongPassphraseException();
  @override
  String toString() => 'Wrong passphrase.';
}

/// Everything [StoreDatabase] persists: preference values by key, and the
/// connection list with every per-connection bag.
class StoreSnapshot {
  const StoreSnapshot({required this.preferences, required this.connections});

  static const empty = StoreSnapshot(preferences: {}, connections: []);

  /// `String`, `int` (booleans as 0/1) or `double` values.
  final Map<String, Object> preferences;
  final List<ConnectionConfig> connections;
}

/// The settings store: one SQLite file sealed with SQLCipher-compatible
/// encryption (SQLite3MultipleCiphers in `sqlcipher` / legacy-4 mode —
/// AES-256, HMAC-SHA512 page authentication, PBKDF2-HMAC-SHA512 with 256 000
/// iterations). Any SQLCipher 4 tool can open it with the passphrase.
///
/// Reads and writes are whole snapshots: [save] replaces every row in one
/// transaction, so a crash leaves either the previous state or the new one.
class StoreDatabase {
  /// Wraps an already-open, already-keyed database.
  StoreDatabase(this._db) {
    _migrate();
  }

  /// Opens (creating when missing) the store at [path] under [passphrase].
  /// Throws [WrongPassphraseException] when the file exists but the
  /// passphrase doesn't open it.
  factory StoreDatabase.open(String path, String passphrase) {
    final db = sqlite3.open(path);
    try {
      _applyKey(db, passphrase);
      // The key is only checked on first page read.
      db.select('SELECT count(*) FROM sqlite_master');
    } on SqliteException {
      db.close();
      throw const WrongPassphraseException();
    }
    return StoreDatabase(db);
  }

  /// An unencrypted in-memory store, for tests.
  factory StoreDatabase.inMemory() => StoreDatabase(sqlite3.openInMemory());

  final Database _db;

  static const String fileName = 'store.sqlite';

  /// `<Application Support>/com.jwo1f.aperture/store.sqlite`.
  static Future<String> defaultPath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/$fileName';
  }

  static bool exists(String path) => File(path).existsSync();

  /// Deletes the store and its journal. Irreversible: this is the way out
  /// of a forgotten passphrase.
  static void erase(String path) {
    for (final suffix in const ['', '-journal', '-wal', '-shm']) {
      final f = File('$path$suffix');
      if (f.existsSync()) f.deleteSync();
    }
  }

  /// Both pragmas must precede the key on every open, or the file is read
  /// under the library's default cipher and rejected.
  static void _applyKey(Database db, String passphrase) {
    db.execute("PRAGMA cipher = 'sqlcipher'");
    db.execute('PRAGMA legacy = 4');
    db.execute("PRAGMA key = ${_quote(passphrase)}");
  }

  static String _quote(String s) => "'${s.replaceAll("'", "''")}'";

  /// Re-encrypts every page under [passphrase].
  void rekey(String passphrase) {
    _db.execute("PRAGMA rekey = ${_quote(passphrase)}");
  }

  void close() => _db.close();

  // ---- schema -------------------------------------------------------

  static const int _schemaVersion = 2;

  void _migrate() {
    final version = _db.select('PRAGMA user_version').single.columnAt(0);
    if (version == _schemaVersion) return;
    if (version == 1) {
      // The boolean `use_ssl` becomes a [TlsMode] index; its 0 / 1 are
      // already `off` / `require`.
      _db.execute('''
        BEGIN;
        ALTER TABLE connections RENAME COLUMN use_ssl TO tls_mode;
        PRAGMA user_version = $_schemaVersion;
        COMMIT;
      ''');
      return;
    }
    if (version != 0) {
      throw StateError(
        'store.sqlite has schema version $version; this build knows '
        '$_schemaVersion',
      );
    }
    _db.execute('''
      BEGIN;
      CREATE TABLE preferences (
        key   TEXT PRIMARY KEY,
        value ANY NOT NULL
      ) STRICT;
      CREATE TABLE connections (
        id                TEXT PRIMARY KEY,
        position          INTEGER NOT NULL,
        name              TEXT NOT NULL,
        engine            TEXT NOT NULL,
        host              TEXT NOT NULL,
        port              INTEGER NOT NULL,
        database          TEXT NOT NULL,
        username          TEXT NOT NULL,
        file_path         TEXT NOT NULL,
        credential_kind   TEXT NOT NULL,
        credential_value  TEXT NOT NULL,
        tls_mode          INTEGER NOT NULL,
        read_only         INTEGER NOT NULL,
        color             INTEGER,
        last_connected_at INTEGER
      ) STRICT;
      CREATE TABLE favorite_tables (
        connection_id TEXT NOT NULL REFERENCES connections ON DELETE CASCADE,
        table_key     TEXT NOT NULL,
        PRIMARY KEY (connection_id, table_key)
      ) STRICT;
      CREATE TABLE recent_tables (
        connection_id TEXT NOT NULL REFERENCES connections ON DELETE CASCADE,
        position      INTEGER NOT NULL,
        table_key     TEXT NOT NULL,
        PRIMARY KEY (connection_id, position)
      ) STRICT;
      CREATE TABLE table_use_counts (
        connection_id TEXT NOT NULL REFERENCES connections ON DELETE CASCADE,
        table_key     TEXT NOT NULL,
        count         INTEGER NOT NULL,
        PRIMARY KEY (connection_id, table_key)
      ) STRICT;
      CREATE TABLE column_widths (
        connection_id TEXT NOT NULL REFERENCES connections ON DELETE CASCADE,
        table_key     TEXT NOT NULL,
        column_name   TEXT NOT NULL,
        width         REAL NOT NULL,
        PRIMARY KEY (connection_id, table_key, column_name)
      ) STRICT;
      CREATE TABLE saved_queries (
        connection_id TEXT NOT NULL REFERENCES connections ON DELETE CASCADE,
        id            TEXT NOT NULL,
        position      INTEGER NOT NULL,
        name          TEXT NOT NULL,
        sql           TEXT NOT NULL,
        updated_at    INTEGER,
        PRIMARY KEY (connection_id, position)
      ) STRICT;
      CREATE TABLE query_messages (
        connection_id TEXT NOT NULL REFERENCES connections ON DELETE CASCADE,
        query_id      TEXT NOT NULL,
        position      INTEGER NOT NULL,
        at            INTEGER NOT NULL,
        sql           TEXT NOT NULL,
        elapsed_ms    INTEGER,
        affected_rows INTEGER,
        error         TEXT,
        PRIMARY KEY (connection_id, query_id, position)
      ) STRICT;
      PRAGMA user_version = $_schemaVersion;
      COMMIT;
    ''');
  }

  // ---- read ---------------------------------------------------------

  StoreSnapshot load() {
    final preferences = <String, Object>{
      for (final r in _db.select('SELECT key, value FROM preferences'))
        r['key'] as String: r['value'] as Object,
    };

    Map<String, List<Row>> byConnection(String sql) {
      final out = <String, List<Row>>{};
      for (final r in _db.select(sql)) {
        out.putIfAbsent(r['connection_id'] as String, () => []).add(r);
      }
      return out;
    }

    final favorites = byConnection(
      'SELECT connection_id, table_key FROM favorite_tables',
    );
    final recents = byConnection(
      'SELECT connection_id, table_key FROM recent_tables '
      'ORDER BY connection_id, position',
    );
    final counts = byConnection(
      'SELECT connection_id, table_key, count FROM table_use_counts',
    );
    final widths = byConnection(
      'SELECT connection_id, table_key, column_name, width FROM column_widths',
    );
    final queries = byConnection(
      'SELECT connection_id, id, name, sql, updated_at FROM saved_queries '
      'ORDER BY connection_id, position',
    );
    final messages = byConnection(
      'SELECT connection_id, query_id, at, sql, elapsed_ms, affected_rows, '
      'error FROM query_messages ORDER BY connection_id, query_id, position',
    );

    final connections = <ConnectionConfig>[];
    for (final r in _db.select('SELECT * FROM connections ORDER BY position')) {
      final id = r['id'] as String;
      final columnWidths = <String, Map<String, double>>{};
      for (final w in widths[id] ?? const <Row>[]) {
        final table = columnWidths.putIfAbsent(
          w['table_key'] as String,
          () => {},
        );
        table[w['column_name'] as String] = w['width'] as double;
      }
      final queryMessages = <String, List<QueryMessage>>{};
      for (final m in messages[id] ?? const <Row>[]) {
        queryMessages
            .putIfAbsent(m['query_id'] as String, () => [])
            .add(
              QueryMessage(
                timestamp: _time(m['at'] as int),
                sql: m['sql'] as String,
                elapsedMs: m['elapsed_ms'] as int?,
                affectedRows: m['affected_rows'] as int?,
                error: m['error'] as String?,
              ),
            );
      }
      connections.add(
        ConnectionConfig(
          id: id,
          name: r['name'] as String,
          engine: DbEngine.values.byName(r['engine'] as String),
          host: r['host'] as String,
          port: r['port'] as int,
          database: r['database'] as String,
          username: r['username'] as String,
          filePath: r['file_path'] as String,
          credential: _credential(
            r['credential_kind'] as String,
            r['credential_value'] as String,
          ),
          tls: TlsMode.values[r['tls_mode'] as int],
          readOnly: r['read_only'] == 1,
          color: r['color'] as int?,
          lastConnectedAt: _maybeTime(r['last_connected_at'] as int?),
          favoriteTables: {
            for (final f in favorites[id] ?? const <Row>[])
              f['table_key'] as String,
          },
          recentTables: [
            for (final t in recents[id] ?? const <Row>[])
              t['table_key'] as String,
          ],
          tableUseCounts: {
            for (final c in counts[id] ?? const <Row>[])
              c['table_key'] as String: c['count'] as int,
          },
          columnWidths: columnWidths,
          savedQueries: [
            for (final q in queries[id] ?? const <Row>[])
              SavedQuery(
                id: q['id'] as String,
                name: q['name'] as String,
                sql: q['sql'] as String,
                updatedAt: _maybeTime(q['updated_at'] as int?),
              ),
          ],
          queryMessages: queryMessages,
        ),
      );
    }
    return StoreSnapshot(preferences: preferences, connections: connections);
  }

  static Credential _credential(String kind, String value) => switch (kind) {
    'command' => CommandCredential(value),
    _ => PasswordCredential(value),
  };

  static DateTime _time(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

  static DateTime? _maybeTime(int? ms) => ms == null ? null : _time(ms);

  // ---- write --------------------------------------------------------

  void save(StoreSnapshot snapshot) {
    _db.execute('BEGIN');
    try {
      _writeAll(snapshot);
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _writeAll(StoreSnapshot snapshot) {
    for (final table in const [
      'query_messages',
      'saved_queries',
      'column_widths',
      'table_use_counts',
      'recent_tables',
      'favorite_tables',
      'connections',
      'preferences',
    ]) {
      _db.execute('DELETE FROM $table');
    }

    _insert('INSERT INTO preferences VALUES (?, ?)', [
      for (final e in snapshot.preferences.entries) [e.key, e.value],
    ]);

    final cs = snapshot.connections;
    _insert(
      'INSERT INTO connections VALUES '
      '(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        for (var i = 0; i < cs.length; i++)
          [
            cs[i].id,
            i,
            cs[i].name,
            cs[i].engine.name,
            cs[i].host,
            cs[i].port,
            cs[i].database,
            cs[i].username,
            cs[i].filePath,
            ...switch (cs[i].credential) {
              PasswordCredential(password: final p) => ['password', p],
              CommandCredential(command: final c) => ['command', c],
            },
            cs[i].tls.index,
            cs[i].readOnly ? 1 : 0,
            cs[i].color,
            cs[i].lastConnectedAt?.millisecondsSinceEpoch,
          ],
      ],
    );
    _insert('INSERT INTO favorite_tables VALUES (?, ?)', [
      for (final c in cs)
        for (final t in c.favoriteTables) [c.id, t],
    ]);
    _insert('INSERT INTO recent_tables VALUES (?, ?, ?)', [
      for (final c in cs)
        for (var i = 0; i < c.recentTables.length; i++)
          [c.id, i, c.recentTables[i]],
    ]);
    _insert('INSERT INTO table_use_counts VALUES (?, ?, ?)', [
      for (final c in cs)
        for (final e in c.tableUseCounts.entries) [c.id, e.key, e.value],
    ]);
    _insert('INSERT INTO column_widths VALUES (?, ?, ?, ?)', [
      for (final c in cs)
        for (final t in c.columnWidths.entries)
          for (final w in t.value.entries) [c.id, t.key, w.key, w.value],
    ]);
    _insert('INSERT INTO saved_queries VALUES (?, ?, ?, ?, ?, ?)', [
      for (final c in cs)
        for (var i = 0; i < c.savedQueries.length; i++)
          [
            c.id,
            c.savedQueries[i].id,
            i,
            c.savedQueries[i].name,
            c.savedQueries[i].sql,
            c.savedQueries[i].updatedAt?.millisecondsSinceEpoch,
          ],
    ]);
    _insert('INSERT INTO query_messages VALUES (?, ?, ?, ?, ?, ?, ?, ?)', [
      for (final c in cs)
        for (final e in c.queryMessages.entries)
          for (var i = 0; i < e.value.length; i++)
            [
              c.id,
              e.key,
              i,
              e.value[i].timestamp.millisecondsSinceEpoch,
              e.value[i].sql,
              e.value[i].elapsedMs,
              e.value[i].affectedRows,
              e.value[i].error,
            ],
    ]);
  }

  void _insert(String sql, List<List<Object?>> rows) {
    if (rows.isEmpty) return;
    final stmt = _db.prepare(sql);
    try {
      for (final r in rows) {
        stmt.execute(r);
      }
    } finally {
      stmt.close();
    }
  }
}
