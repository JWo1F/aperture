import '../../../models/db_object.dart';
import '../../../models/query_result.dart';
import '../../../state/catalog_controller.dart';

/// Builds a column-name → FK lookup for a raw query result.
///
/// Prefers the source-relation OID exposed by the wire protocol so the FK
/// action targets the *actual* table the column came from; falls back to the
/// catalog-wide aggregation when the column is an expression (no source
/// relation).
Map<String, DbForeignKey> resolveResultForeignKeys(
  CatalogController catalog,
  QueryResult result,
) {
  final schemas = result.columnSchemas;
  if (schemas == null) return catalog.aggregatedForeignKeys;
  final out = <String, DbForeignKey>{};
  for (final schema in schemas) {
    final precise = catalog.findForeignKey(schema.tableOid, schema.name);
    if (precise != null) {
      out[schema.name] = precise;
    } else if (!schema.hasSourceRelation) {
      final guess = catalog.aggregatedForeignKeys[schema.name];
      if (guess != null) out[schema.name] = guess;
    }
  }
  return out;
}

/// Returns the relation whose PK is [columnName], preferring the source
/// relation OID from the wire protocol when present. Falls back to the
/// ambiguity-safe catalog lookup otherwise.
DbTable? findResultRowOwner(
  CatalogController catalog,
  QueryResult result,
  String columnName,
) {
  final schemas = result.columnSchemas;
  if (schemas == null) return catalog.findPrimaryKeyOwner(columnName);
  for (final schema in schemas) {
    if (schema.name != columnName) continue;
    return catalog.findPrimaryKeyOwnerByOid(schema.tableOid, columnName);
  }
  return catalog.findPrimaryKeyOwner(columnName);
}
