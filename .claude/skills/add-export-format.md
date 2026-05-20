---
name: add-export-format
description: Use when adding a new export output format (JSON, XLSX, NDJSON, TSV, SQL INSERTs, …) to the table-view and query-editor Export action. The interface is small — one subclass + one catalog entry.
---

The exporter system in `lib/services/exporter.dart` is deliberately
extensible. Adding a format takes one subclass, plus a single line to
register it. The dialog UI updates automatically.

## 1. Subclass `ExportFormat`

```dart
class JsonFormat extends ExportFormat {
  const JsonFormat();

  @override
  String get id => 'json';
  @override
  String get label => 'JSON';
  @override
  String get fileExtension => 'json';

  @override
  Future<void> writeFile(File file, QueryResult result) async {
    final sink = file.openWrite();
    try {
      final rows = [
        for (final row in result.rows)
          {
            for (var i = 0; i < result.columns.length; i++)
              result.columns[i]: _rawForJson(row[i]),
          },
      ];
      sink.write(const JsonEncoder.withIndent('  ').convert(rows));
    } finally {
      await sink.flush();
      await sink.close();
    }
  }
}
```

## 2. Format the cell values

For text-based formats (CSV, TSV, SQL INSERT), use `formatCellValue`
from `lib/models/value_format.dart` — it handles the postgres
`UndecodedBytes` / JSON Map quirks. For JSON output, the raw value is
usually closer to what you want — `JsonEncoder` handles Map / List /
num / bool / String / null directly:

```dart
dynamic _rawForJson(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v.toIso8601String();
  if (v is UndecodedBytes) return formatCellValue(v); // text decode
  return v;
}
```

For binary formats (XLSX, Parquet), you'll need a writer package — add
it to `pubspec.yaml` and import inside the format subclass so the
dependency is only paid when the format is used.

## 3. Register the format

`exportFormats` at the bottom of `exporter.dart` is the catalog:

```dart
const List<ExportFormat> exportFormats = [
  CsvFormat(),
  JsonFormat(),
];
```

The export dialog reads this list directly — no UI change needed.

## 4. Verify

- Open a table → toolbar Export icon → format chip should include yours.
- For both scopes (Current page / All filtered rows) verify the output.
- For query tabs (no scope toggle), only "current result" mode runs.
- Open the written file in a text editor or relevant tool and sanity-
  check structure.

## Notes

- The dialog reuses `_swapExtension` to rewrite the suggested filename
  when the user switches format. Make sure your `fileExtension` is just
  the suffix (`json`, not `.json`).
- `file_selector` provides the OS save dialog. You don't need to add
  any platform code — the entitlement is already in place.
- Error reporting: throw from `writeFile` and the dialog will surface
  the message inline. Don't catch + log.

## Checklist

- [ ] New `ExportFormat` subclass with id / label / fileExtension
- [ ] `writeFile` handles NULL, JSON columns, UndecodedBytes, DateTime
- [ ] Catalog entry added to `exportFormats`
- [ ] Tested with a real table → exported file opens cleanly
- [ ] `verify-changes` passes
