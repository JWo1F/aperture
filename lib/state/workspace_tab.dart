import '../models/db_object.dart';
import '../models/query_result.dart';

/// A tab in the center workspace. Either a free-form SQL editor, a data
/// view bound to one relation, or a schema viewer.
sealed class WorkspaceTab {
  WorkspaceTab(this.id);

  final String id;

  /// Per-tab column widths, keyed by column name. Persisted for the tab's
  /// lifetime so resizes survive pagination, filters, sorts, and tab switches.
  final Map<String, double> columnWidths = {};

  String get title;
}

class QueryTab extends WorkspaceTab {
  QueryTab(super.id, {this.name = 'Query', this.sql = ''});

  /// Display name shown in the tab strip + sidebar. User-renamable via
  /// the sidebar context menu; auto-incremented as `Query 1`, `Query 2`,
  /// … when created via the toolbar / ⌘N path.
  String name;
  String sql;
  QueryResult? result;
  bool running = false;

  @override
  String get title => name;
}

/// Read-only view of a table's DDL (CREATE TABLE, indexes, FKs).
class SchemaTab extends WorkspaceTab {
  SchemaTab(super.id, this.table);

  final DbTable table;
  String? ddl;
  String? error;
  bool loading = false;

  @override
  String get title => '${table.name} · schema';
}

/// One pending cell edit, keyed by grid row and column index.
class CellEdit {
  CellEdit(this.row, this.column);

  final int row;
  final int column;

  @override
  bool operator ==(Object other) =>
      other is CellEdit && other.row == row && other.column == column;

  @override
  int get hashCode => Object.hash(row, column);
}

/// What a cell is being changed to. Either a literal text value (null = SQL
/// NULL) or the special `DEFAULT` directive.
sealed class CellEditValue {
  const CellEditValue();
}

class CellLiteral extends CellEditValue {
  const CellLiteral(this.value);
  final String? value;
}

class CellDefault extends CellEditValue {
  const CellDefault();
}

class TableTab extends WorkspaceTab {
  TableTab(super.id, this.table);

  final DbTable table;

  QueryResult? result;
  bool loading = false;
  bool applying = false;
  int page = 0;
  int pageSize = 100;
  int totalRows = 0;

  /// Column projection — a raw SQL select list. Defaults to `*` (all columns).
  String selectList = '*';

  /// Active row filter — a raw SQL `WHERE` fragment typed by the user.
  String filter = '';

  /// Active sort — a raw SQL `ORDER BY` fragment, also driven by header clicks.
  String orderBy = '';

  /// Pending, un-applied cell edits.
  final Map<CellEdit, CellEditValue> edits = {};

  bool get hasEdits => edits.isNotEmpty;

  int get pageCount => totalRows == 0 ? 1 : ((totalRows - 1) ~/ pageSize) + 1;
  int get offset => page * pageSize;

  @override
  String get title => table.name;
}
