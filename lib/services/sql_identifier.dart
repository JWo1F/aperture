/// Helpers for safely embedding identifiers and literals in dynamically
/// constructed SQL.
///
/// Hand-rolling `"$col"` drops the escaping: a column literally named
/// `weird"name` would render as `"weird"name"`, which either errors or
/// parses as something else entirely. Every identifier and literal the app
/// builds goes through the [SqlDialect] of the connection it is bound for.
library;

const _nul = '\u0000';

/// How an engine spells identifiers and string literals.
enum SqlDialect {
  /// Postgres and SQLite: `"identifier"` with `""` doubled, `'literal'` with
  /// `''` doubled and backslash taken literally.
  ansi,

  /// MySQL and MariaDB: `` `identifier` `` with ``` `` ``` doubled. Inside a
  /// `'literal'` the backslash is an escape character, so it is doubled too.
  /// A server running with `NO_BACKSLASH_ESCAPES` would store both.
  mysql;

  /// Quotes [name] as an identifier. NUL bytes are rejected: no engine
  /// accepts one inside an identifier, so one means caller corruption.
  String quoteIdent(String name) {
    if (name.contains(_nul)) {
      throw ArgumentError.value(
        name,
        'name',
        'identifiers cannot contain NUL bytes',
      );
    }
    return switch (this) {
      ansi => '"${name.replaceAll('"', '""')}"',
      mysql => '`${name.replaceAll('`', '``')}`',
    };
  }

  /// Quotes a schema-qualified name — `"schema"."name"` /
  /// `` `db`.`name` ``.
  String qualify(String schema, String name) =>
      '${quoteIdent(schema)}.${quoteIdent(name)}';

  /// Renders [value] as a SQL string literal, or `NULL`. Strings stay
  /// untyped so the engine coerces them into the target column type.
  String literal(String? value) {
    if (value == null) return 'NULL';
    final escaped = switch (this) {
      ansi => value.replaceAll("'", "''"),
      mysql => value.replaceAll(r'\', r'\\').replaceAll("'", "''"),
    };
    return "'$escaped'";
  }
}
