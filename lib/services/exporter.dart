import 'dart:io';

import '../models/query_result.dart';
import '../models/value_format.dart';

/// One supported output format. Add a subclass + extend [exportFormats] to
/// surface a new format in the export dialog — no other call sites change.
///
/// Implementations return the full rendered text via [render]; the default
/// [writeFile] just persists that string. This keeps a single code path for
/// file save and clipboard copy and is fine for a personal tool — multi-million
/// row exports would want streaming, but we don't have that use case.
abstract class ExportFormat {
  const ExportFormat();

  String get id;
  String get label;
  String get fileExtension;

  String render(QueryResult result);

  Future<void> writeFile(File file, QueryResult result) =>
      file.writeAsString(render(result));
}

/// CSV — RFC 4180 quoting: only quote when a field contains a separator,
/// quote, CR, or LF; escape inner quotes by doubling them.
class CsvFormat extends ExportFormat {
  const CsvFormat();

  @override
  String get id => 'csv';

  @override
  String get label => 'CSV';

  @override
  String get fileExtension => 'csv';

  @override
  String render(QueryResult result) {
    final buf = StringBuffer();
    buf.write(_renderRow(result.columns));
    buf.write('\r\n');
    for (final row in result.rows) {
      buf.write(_renderRow(row.map(_cellText).toList()));
      buf.write('\r\n');
    }
    return buf.toString();
  }

  String _renderRow(List<String> cells) => cells.map(_escape).join(',');

  /// Renders a raw cell value using the same formatter the grid uses — so
  /// JSON columns export as JSON, dates as ISO strings, etc. SQL NULL becomes
  /// an empty cell (the most widely-compatible choice for CSV).
  String _cellText(dynamic raw) => formatCellValue(raw) ?? '';

  String _escape(String text) {
    final needsQuoting = text.contains(',') ||
        text.contains('"') ||
        text.contains('\n') ||
        text.contains('\r');
    if (!needsQuoting) return text;
    return '"${text.replaceAll('"', '""')}"';
  }
}

/// GitHub-Flavored Markdown table.
///
/// Column widths are padded to the widest cell so the raw output is also
/// readable in a plain editor. Pipes inside cells are escaped (`\|`) and
/// embedded newlines collapse to `<br>` since GFM tables can't span lines.
class MarkdownFormat extends ExportFormat {
  const MarkdownFormat();

  @override
  String get id => 'markdown';

  @override
  String get label => 'Markdown';

  @override
  String get fileExtension => 'md';

  @override
  String render(QueryResult result) {
    final columns = result.columns;
    if (columns.isEmpty) return '';

    final headerCells = columns.map(_escape).toList();
    final bodyCells = result.rows
        .map((row) => row.map((c) => _escape(_cellText(c))).toList())
        .toList();

    final widths = List<int>.generate(columns.length, (i) {
      var max = headerCells[i].length;
      for (final row in bodyCells) {
        if (i < row.length && row[i].length > max) max = row[i].length;
      }
      // GFM requires at least three dashes in the separator row.
      return max < 3 ? 3 : max;
    });

    final buf = StringBuffer();
    _writeRow(buf, headerCells, widths);
    _writeSeparator(buf, widths);
    for (final row in bodyCells) {
      _writeRow(buf, row, widths);
    }
    return buf.toString();
  }

  void _writeRow(StringBuffer buf, List<String> cells, List<int> widths) {
    buf.write('|');
    for (var i = 0; i < widths.length; i++) {
      final cell = i < cells.length ? cells[i] : '';
      buf.write(' ');
      buf.write(cell.padRight(widths[i]));
      buf.write(' |');
    }
    buf.write('\n');
  }

  void _writeSeparator(StringBuffer buf, List<int> widths) {
    buf.write('|');
    for (final w in widths) {
      buf.write(' ');
      buf.write('-' * w);
      buf.write(' |');
    }
    buf.write('\n');
  }

  String _cellText(dynamic raw) => formatCellValue(raw) ?? '';

  String _escape(String text) => text
      .replaceAll(r'\', r'\\')
      .replaceAll('|', r'\|')
      .replaceAll('\r\n', '<br>')
      .replaceAll('\n', '<br>')
      .replaceAll('\r', '<br>');
}

/// Catalog of available formats. New formats only need to be appended here.
const List<ExportFormat> exportFormats = [
  CsvFormat(),
  MarkdownFormat(),
];
