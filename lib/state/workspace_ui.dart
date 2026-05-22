import 'package:flutter/foundation.dart';

/// View-side state for the workspace shell: which schema headers are
/// expanded in the sidebar tree, and the current sidebar-search text.
///
/// Nothing here is persisted across sessions and nothing here depends on
/// the live connection — it's purely a chrome notifier so the schema tree
/// can rebuild without dragging in unrelated catalog or tab work.
class WorkspaceUi extends ChangeNotifier {
  final Set<String> _expandedSchemas = {};

  /// Expanded nodes inside the table tree — table rows and their detail
  /// folders (columns / keys / foreign keys / indexes). Keyed by an opaque id
  /// the sidebar builds; this notifier never interprets it.
  final Set<String> _expandedNodes = {};

  String _sidebarSearch = '';

  bool isSchemaExpanded(String name) => _expandedSchemas.contains(name);

  bool isNodeExpanded(String id) => _expandedNodes.contains(id);

  void toggleNode(String id) {
    if (!_expandedNodes.remove(id)) _expandedNodes.add(id);
    notifyListeners();
  }

  String get sidebarSearch => _sidebarSearch;

  void setSidebarSearch(String value) {
    if (_sidebarSearch == value) return;
    _sidebarSearch = value;
    notifyListeners();
  }

  void toggleSchema(String name) {
    if (!_expandedSchemas.remove(name)) _expandedSchemas.add(name);
    notifyListeners();
  }

  /// Expand the only schema in a freshly-loaded catalog so the user sees
  /// its tables without an explicit click.
  void expandSingleSchema(String name) {
    if (_expandedSchemas.add(name)) notifyListeners();
  }

  /// Reset to defaults on disconnect.
  void reset() {
    final wasDirty = _expandedSchemas.isNotEmpty ||
        _expandedNodes.isNotEmpty ||
        _sidebarSearch.isNotEmpty;
    _expandedSchemas.clear();
    _expandedNodes.clear();
    _sidebarSearch = '';
    if (wasDirty) notifyListeners();
  }
}
