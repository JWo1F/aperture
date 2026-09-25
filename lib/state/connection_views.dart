import '../models/connection_config.dart';
import '../models/db_object.dart';
import 'catalog_controller.dart';
import 'session_controller.dart';

/// Resolve the active connection's qualified-key bags into the [DbTable]
/// objects from the currently-loaded catalog. Pure derivations so they
/// stay out of [AppStore] (which knows nothing about the catalog).

Map<String, DbTable> _tableLookup(CatalogController catalog) => {
  for (final s in catalog.schemas)
    for (final t in s.tables) t.qualifiedKey: t,
};

List<DbTable> recentTablesView(
  ConnectionConfig? conn,
  CatalogController catalog,
) {
  if (conn == null || conn.recentTables.isEmpty) return const [];
  final lookup = _tableLookup(catalog);
  return [
    for (final key in conn.recentTables)
      if (lookup[key] != null) lookup[key]!,
  ];
}

List<DbTable> favoriteTablesView(
  ConnectionConfig? conn,
  CatalogController catalog,
) {
  final keys = conn?.favoriteTables;
  if (keys == null || keys.isEmpty) return const [];
  final lookup = _tableLookup(catalog);
  return [
    for (final key in keys)
      if (lookup[key] != null) lookup[key]!,
  ];
}

List<DbTable> frequentTablesView(
  ConnectionConfig? conn,
  CatalogController catalog, {
  int limit = 5,
}) {
  if (conn == null || conn.tableUseCounts.isEmpty) return const [];
  final lookup = _tableLookup(catalog);
  final ranked = conn.tableUseCounts.entries
      .where((e) => lookup.containsKey(e.key))
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [for (final e in ranked.take(limit)) lookup[e.key]!];
}

bool isFavoriteTable(ConnectionConfig? conn, DbTable table) {
  final keys = conn?.favoriteTables ?? const <String>{};
  return keys.contains(table.qualifiedKey);
}

/// True when the shell shows the workspace rather than the welcome screen.
/// The welcome screen stays up through the connect → phase-0 gap so the
/// workspace doesn't pop in with zero schemas; a lost connection keeps the
/// workspace, since the prior session's catalog is still meaningful.
bool workspaceVisible(SessionController session, CatalogController catalog) {
  final status = session.status;
  return (status == ConnectionStatus.connected && catalog.hasSchemas) ||
      status == ConnectionStatus.lost;
}
