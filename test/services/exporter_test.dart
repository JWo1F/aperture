import 'dart:io';
import 'dart:typed_data';

import 'package:aperture/models/query_result.dart';
import 'package:aperture/services/exporter.dart';
import 'package:flutter_test/flutter_test.dart';

QueryResult _result(List<String> columns, List<List<Object?>> rows) =>
    QueryResult.rows(columns: columns, rows: rows, elapsed: Duration.zero);

const _csv = CsvFormat();
const _md = MarkdownFormat();

void main() {
  group('CsvFormat', () {
    test('quotes only what RFC 4180 requires', () {
      final out = _csv.render(
        _result(
          ['plain', 'comma', 'quote', 'newline'],
          [
            ['a', 'b,c', 'say "hi"', 'x\ny'],
          ],
        ),
      );
      expect(
        out,
        'plain,comma,quote,newline\r\n'
        'a,"b,c","say ""hi""","x\ny"\r\n',
      );
    });

    test('every row ends CRLF, header included', () {
      final out = _csv.render(_result(['a'], [['1'], ['2']]));
      expect(out, 'a\r\n1\r\n2\r\n');
    });

    test('a NULL cell exports empty, not the word NULL', () {
      final out = _csv.render(_result(['a', 'b'], [[null, 'x']]));
      expect(out, 'a,b\r\n,x\r\n');
    });

    test('binary exports every byte, not the grid preview', () {
      // formatCellValue elides at 16 bytes for the grid; an export that
      // did the same would pass off the head of a blob as the value.
      final bytes = Uint8List.fromList(List<int>.generate(40, (i) => i));
      final out = _csv.render(_result(['b'], [[bytes]]));
      expect(out, contains('2021222324252627'));
      expect(out, isNot(contains('…')));
    });

    test('a carriage return alone still forces quoting', () {
      final out = _csv.render(_result(['a'], [['x\ry']]));
      expect(out, 'a\r\n"x\ry"\r\n');
    });

    test('render and writeStream agree byte for byte', () async {
      final result = _result(
        ['a', 'b'],
        [
          ['1', 'x,y'],
          [null, 'say "hi"'],
        ],
      );
      final tmp = await Directory.systemTemp.createTemp('aperture_csv');
      final file = File('${tmp.path}/out.csv');
      await _csv.writeFile(file, result);
      expect(await file.readAsString(), _csv.render(result));
      await tmp.delete(recursive: true);
    });
  });

  group('MarkdownFormat', () {
    test('escapes pipes and backslashes, folds newlines to <br>', () {
      final out = _md.render(
        _result(['a'], [[r'pipe | and \slash']], ),
      );
      expect(out, contains(r'pipe \| and \\slash'));

      final multi = _md.render(_result(['a'], [['x\r\ny\nz\rw']]));
      expect(multi, contains('x<br>y<br>z<br>w'));
    });

    test('pads to the widest cell, minimum three', () {
      final out = _md.render(_result(['a'], [['1']]));
      final lines = out.trim().split('\n');
      expect(lines[0], '| a   |');
      expect(lines[1], '| --- |');
      expect(lines[2], '| 1   |');
    });

    test('a result with no columns renders nothing', () {
      expect(_md.render(_result([], [])), '');
    });

    test('render and writeStream agree byte for byte', () async {
      final result = _result(['a', 'bbbb'], [['1', 'x'], [null, 'yy']]);
      final tmp = await Directory.systemTemp.createTemp('aperture_md');
      final file = File('${tmp.path}/out.md');
      await _md.writeFile(file, result);
      expect(await file.readAsString(), _md.render(result));
      await tmp.delete(recursive: true);
    });
  });

  group('cancellation and failure leave no partial file', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('aperture_export');
    });

    tearDown(() => tmp.delete(recursive: true));

    test('a cancelled export deletes its output', () async {
      final file = File('${tmp.path}/cancelled.csv');
      final cancel = CancelToken()..cancel();
      await expectLater(
        _csv.writeFile(
          file,
          _result(['a'], List.generate(5000, (i) => ['$i'])),
          cancel: cancel,
        ),
        throwsA(isA<ExportCancelledException>()),
      );
      expect(file.existsSync(), isFalse);
    });

    test('a cancel partway through still deletes the output', () async {
      final file = File('${tmp.path}/midway.csv');
      final cancel = CancelToken();
      // The writer checks every 1024 rows, so fire after the first yield.
      Future<void>.delayed(Duration.zero, cancel.cancel);
      await expectLater(
        _csv.writeFile(
          file,
          _result(['a'], List.generate(20000, (i) => ['$i'])),
          cancel: cancel,
        ),
        throwsA(isA<ExportCancelledException>()),
      );
      expect(file.existsSync(), isFalse);
    });

    test('a formatter that throws leaves nothing behind', () async {
      final file = File('${tmp.path}/broken.csv');
      await expectLater(
        _ExplodingFormat().writeFile(file, _result(['a'], [['1']])),
        throwsA(isA<StateError>()),
      );
      // A short file at the path the user picked reads as a complete
      // export; absence does not.
      expect(file.existsSync(), isFalse);
    });

    test('a successful export keeps its output', () async {
      final file = File('${tmp.path}/fine.csv');
      await _csv.writeFile(file, _result(['a'], [['1']]));
      expect(file.existsSync(), isTrue);
      expect(await file.readAsString(), 'a\r\n1\r\n');
    });
  });

  group('exportFormats', () {
    test('ids and extensions are unique', () {
      expect(
        exportFormats.map((f) => f.id).toSet().length,
        exportFormats.length,
      );
      expect(
        exportFormats.map((f) => f.fileExtension).toSet().length,
        exportFormats.length,
      );
    });
  });
}

class _ExplodingFormat extends ExportFormat {
  @override
  String get id => 'boom';

  @override
  String get label => 'Boom';

  @override
  String get fileExtension => 'boom';

  @override
  String render(QueryResult result) => throw StateError('boom');

  @override
  Future<void> writeStream(
    IOSink sink,
    QueryResult result, {
    CancelToken? cancel,
  }) async {
    sink.write('partial output');
    throw StateError('boom');
  }
}
