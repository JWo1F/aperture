import 'dart:async';
import 'dart:io';

import '../models/query_result.dart';
import '../models/value_format.dart';

/// Lightweight cancel signal threaded through export pipelines. Tests
/// can construct one directly; the UI flips [cancel] on a button press.
class CancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// Thrown by [ExportFormat.writeStream] when the cancel token fires.
/// Callers should catch and delete the partial file.
class ExportCancelledException implements Exception {
  const ExportCancelledException();

  @override
  String toString() => 'Export cancelled';
}

/// One supported output format. Add a subclass + extend [exportFormats] to
/// surface a new format in the export dialog — no other call sites change.
///
/// [render] returns the fully rendered text — used by the clipboard path
/// where we have to hand the OS a single String. [writeStream] writes
/// directly to an [IOSink] without materialising the whole output in the
/// heap, used for file exports.
abstract class ExportFormat {
  const ExportFormat();

  String get id;

  String get label;

  String get fileExtension;

  String render(QueryResult result);

  Future<void> writeStream(
    IOSink sink,
    QueryResult result, {
    CancelToken? cancel,
  });

  /// Streams the export to [file].
  ///
  /// A file that doesn't exist is a clearer outcome than one that does but
  /// is short, so the partial output is removed on *any* failure, not just
  /// on cancel. A truncated CSV sitting at the path the user chose is
  /// indistinguishable from a complete one.
  Future<void> writeFile(
    File file,
    QueryResult result, {
    CancelToken? cancel,
  }) async {
    final sink = file.openWrite();
    var failed = false;
    try {
      await writeStream(sink, result, cancel: cancel);
      await sink.flush();
    } catch (_) {
      failed = true;
      rethrow;
    } finally {
      // Close before deleting: the handle still holds buffered bytes, and
      // on a cancel we want them dropped rather than flushed.
      try {
        await sink.close();
      } catch (_) {
        failed = true;
      }
      if (failed && await file.exists()) {
        try {
          await file.delete();
        } catch (_) {
          // Nothing useful to do — the original failure is what matters.
        }
      }
    }
  }

  String cellText(Object? raw) => exactCellValue(raw) ?? '';

  void checkCancelled(CancelToken? token) {
    if (token?.isCancelled == true) throw const ExportCancelledException();
  }
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
      buf.write(_renderRow(row.map(cellText).toList()));
      buf.write('\r\n');
    }
    return buf.toString();
  }

  @override
  Future<void> writeStream(
    IOSink sink,
    QueryResult result, {
    CancelToken? cancel,
  }) async {
    sink.write(_renderRow(result.columns));
    sink.write('\r\n');
    var i = 0;
    for (final row in result.rows) {
      if ((i++ & 1023) == 0) {
        checkCancelled(cancel);
        // Yield to the event loop every 1024 rows so the UI stays
        // responsive and the cancel button can fire.
        await Future<void>.delayed(Duration.zero);
      }
      sink.write(_renderRow(row.map(cellText).toList()));
      sink.write('\r\n');
    }
  }

  String _renderRow(List<String> cells) => cells.map(_escape).join(',');

  String _escape(String text) {
    final needsQuoting =
        text.contains(',') ||
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
///
/// Markdown requires a first pass over the data to compute widths, so
/// the streaming variant isn't truly streaming for this format — the
/// rendered cell table is held in memory before being written out.
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
        .map((row) => row.map((c) => _escape(cellText(c))).toList())
        .toList();

    final widths = List<int>.generate(columns.length, (i) {
      var max = headerCells[i].length;
      for (final row in bodyCells) {
        if (i < row.length && row[i].length > max) max = row[i].length;
      }
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

  @override
  Future<void> writeStream(
    IOSink sink,
    QueryResult result, {
    CancelToken? cancel,
  }) async {
    final columns = result.columns;
    if (columns.isEmpty) return;

    final headerCells = columns.map(_escape).toList();
    final bodyCells = <List<String>>[];
    var i = 0;
    for (final row in result.rows) {
      if ((i++ & 1023) == 0) {
        checkCancelled(cancel);
        await Future<void>.delayed(Duration.zero);
      }
      bodyCells.add(row.map((c) => _escape(cellText(c))).toList());
    }

    final widths = List<int>.generate(columns.length, (i) {
      var max = headerCells[i].length;
      for (final row in bodyCells) {
        if (i < row.length && row[i].length > max) max = row[i].length;
      }
      return max < 3 ? 3 : max;
    });

    _sinkRow(sink, headerCells, widths);
    _sinkSeparator(sink, widths);
    for (final row in bodyCells) {
      _sinkRow(sink, row, widths);
    }
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

  void _sinkRow(IOSink sink, List<String> cells, List<int> widths) {
    sink.write('|');
    for (var i = 0; i < widths.length; i++) {
      final cell = i < cells.length ? cells[i] : '';
      sink.write(' ');
      sink.write(cell.padRight(widths[i]));
      sink.write(' |');
    }
    sink.write('\n');
  }

  void _sinkSeparator(IOSink sink, List<int> widths) {
    sink.write('|');
    for (final w in widths) {
      sink.write(' ');
      sink.write('-' * w);
      sink.write(' |');
    }
    sink.write('\n');
  }

  String _escape(String text) => text
      .replaceAll(r'\', r'\\')
      .replaceAll('|', r'\|')
      .replaceAll('\r\n', '<br>')
      .replaceAll('\n', '<br>')
      .replaceAll('\r', '<br>');
}

/// Catalog of available formats. New formats only need to be appended here.
const List<ExportFormat> exportFormats = [CsvFormat(), MarkdownFormat()];
