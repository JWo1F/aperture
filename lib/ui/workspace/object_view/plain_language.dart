import '../../../models/db_object.dart';

/// A column type in words someone who doesn't write SQL would use:
/// `character varying(80)` → "Text, up to 80 characters". [enums] and
/// [domains] let user-defined types read as what they hold. A type this
/// doesn't recognise comes back as written.
String plainType(
  String dataType, {
  List<DbEnum> enums = const [],
  List<DbDomain> domains = const [],
}) {
  final raw = dataType.trim();
  if (raw.endsWith('[]')) {
    final inner = plainType(
      raw.substring(0, raw.length - 2),
      enums: enums,
      domains: domains,
    );
    return 'List of ${_lowerFirst(inner)}';
  }

  final bare = _unqualified(raw);
  for (final e in enums) {
    if (e.name == bare) return _oneOf(e.labels);
  }
  for (final d in domains) {
    if (d.name == bare) {
      return plainType(d.baseType, enums: enums, domains: domains);
    }
  }

  final t = raw.toLowerCase();
  final size = RegExp(r'\((\d+)(?:\s*,\s*(\d+))?\)').firstMatch(t);
  final n = size?.group(1);
  final scale = size?.group(2);
  final base = t.replaceAll(RegExp(r'\s*\(.*\)'), '').trim();

  switch (base) {
    case 'smallint' || 'int2' || 'integer' || 'int' || 'int4' || 'serial':
    case 'smallserial' || 'mediumint' || 'tinyint':
      return 'Whole number';
    case 'bigint' || 'int8' || 'bigserial':
      return 'Whole number (large)';
    case 'numeric' || 'decimal':
      if (scale != null && scale != '0') {
        return 'Exact number, $scale decimal ${scale == '1' ? 'place' : 'places'}';
      }
      return scale == '0' ? 'Whole number' : 'Exact number';
    case 'real' || 'float4' || 'double precision' || 'float8' || 'float':
    case 'double':
      return 'Number with decimals (approximate)';
    case 'money':
      return 'Amount of money';
    case 'text' || 'clob' || 'citext' || 'name':
      return 'Text';
    case 'character varying' || 'varchar' || 'nvarchar':
      return n == null ? 'Text' : 'Text, up to $n characters';
    case 'character' || 'char' || 'bpchar' || 'nchar':
      return n == null || n == '1'
          ? 'A single character'
          : 'Text, exactly $n characters';
    case 'boolean' || 'bool':
      return 'Yes or no';
    case 'date':
      return 'Date';
    case 'timestamp without time zone' || 'timestamp' || 'datetime':
      return 'Date and time';
    case 'timestamp with time zone' || 'timestamptz':
      return 'Date and time, with time zone';
    case 'time without time zone' || 'time':
      return 'Time of day';
    case 'time with time zone' || 'timetz':
      return 'Time of day, with time zone';
    case 'interval':
      return 'Length of time';
    case 'uuid':
      return 'Unique identifier';
    case 'json' || 'jsonb':
      return 'Structured data (JSON)';
    case 'xml':
      return 'Structured data (XML)';
    case 'bytea' || 'blob':
      return 'File or binary data';
    case 'inet' || 'cidr':
      return 'Network address';
    case 'macaddr' || 'macaddr8':
      return 'Hardware (MAC) address';
    case 'tsvector':
      return 'Text prepared for search';
    case 'point' || 'line' || 'lseg' || 'box' || 'path' || 'polygon':
    case 'circle' || 'geometry' || 'geography':
      return 'Shape or location';
  }
  // SQLite's affinity rule: a declared type containing INT is an integer,
  // CHAR/CLOB/TEXT is text, REAL/FLOA/DOUB is floating point.
  if (base.contains('int')) return 'Whole number';
  if (base.contains('char') || base.contains('text')) return 'Text';
  if (base.contains('real') || base.contains('floa') || base.contains('doub')) {
    return 'Number with decimals (approximate)';
  }
  return raw;
}

/// "One of: draft, sent or paid", shortened past five values.
String _oneOf(List<String> labels) {
  if (labels.isEmpty) return 'One of a fixed set of values';
  if (labels.length > 5) {
    return 'One of ${labels.length} values: ${labels.take(4).join(', ')}, …';
  }
  if (labels.length == 1) return 'Always "${labels.single}"';
  final head = labels.sublist(0, labels.length - 1).join(', ');
  return 'One of: $head or ${labels.last}';
}

String _unqualified(String type) {
  final dot = type.lastIndexOf('.');
  final name = dot == -1 ? type : type.substring(dot + 1);
  return name.replaceAll('"', '');
}

String _lowerFirst(String s) =>
    s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

/// `order_items` → "order items": how a table reads in a sentence.
String plainName(String identifier) =>
    identifier.replaceAll(RegExp(r'[_\-]+'), ' ').trim();

/// "email" / "first name and last name".
String plainColumns(List<String> columns) {
  final names = columns.map(plainName).toList();
  if (names.length <= 1) return names.join();
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

/// What an index does for the reader, not how it's built.
String plainIndex(DbIndex index) {
  final cols = plainColumns(index.columns);
  if (cols.isEmpty) {
    return index.unique
        ? 'Keeps a computed value unique'
        : 'Speeds up searches on a computed value';
  }
  return index.unique
      ? 'No two rows can share the same $cols'
      : 'Quick to find rows by $cols';
}
