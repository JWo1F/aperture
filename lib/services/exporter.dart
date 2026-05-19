import 'dart:io';

import '../models/query_result.dart';
import '../models/value_format.dart';

/// One supported output format. Add a subclass + extend [exportFormats] to
/// surface a new format in the export dialog — no other call sites change.
abstract class ExportFormat {
  const ExportFormat();

  String get id;
  String get label;
  String get fileExtension;

  Future<void> writeFile(File file, QueryResult result);
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
  Future<void> writeFile(File file, QueryResult result) async {
    final sink = file.openWrite();
    try {
      sink.write(_renderRow(result.columns));
      sink.write('\r\n');
      for (final row in result.rows) {
        sink.write(_renderRow(row.map(_cellText).toList()));
        sink.write('\r\n');
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
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

/// Catalog of available formats. New formats only need to be appended here.
const List<ExportFormat> exportFormats = [
  CsvFormat(),
];
