import 'dart:io';

import 'package:aperture/models/cell_edit.dart';
import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/ui/cell_picker/kinds.dart';
import 'package:aperture/ui/cell_picker/panel.dart';
import 'package:aperture/ui/cell_picker/target.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// The panel sizes in `kinds.dart` are fixed, so the test font's square
// glyphs would measure every label wider than the app ever draws it. Load
// the bundled families so an overflow here is one the user would see.
Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('assets/fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load(AppTheme.uiFamily, [
    'Inter-Regular.ttf',
    'Inter-Medium.ttf',
    'Inter-SemiBold.ttf',
  ]);
  await load(AppTheme.monoFamily, [
    'JetBrainsMono-Regular.ttf',
    'JetBrainsMono-Medium.ttf',
  ]);
  await load('hugeicons', ['hgi-stroke-rounded.ttf']);
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required String dataType,
  Object? value,
  CellEditValue? pending,
  bool canBeNull = true,
  bool hasDefault = true,
}) async {
  final kind = kindFor(value, dataType);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox.fromSize(
            size: kind.size,
            child: Panel(
              kind: kind,
              target: CellEditTarget(
                columnName: 'a_rather_long_column_name',
                originalValue: value,
                pendingEdit: pending,
                canBeNull: canBeNull,
                hasDefault: hasDefault,
                columnDataType: dataType,
              ),
              onCommit: (_) {},
              onRevert: () {},
              onClose: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(_loadFonts);
  tearDown(() => AppColors.setPalette(darkPalette));

  final samples = <(String, Object?)>[
    ('boolean', true),
    ('integer', 42),
    ('numeric', 3.14),
    ('text', 'hello'),
    ('bytea', Uint8List.fromList([1, 2])),
    ('jsonb', {'a': 1}),
    ('integer[]', [1, 2]),
    ('date', DateTime(2026, 9, 28)),
    ('time without time zone', DateTime(2026, 9, 28, 12, 30, 5)),
    ('time with time zone', DateTime(2026, 9, 28, 12, 30, 5)),
    ('timestamp without time zone', DateTime(2026, 9, 28, 12, 30, 5)),
    ('timestamp with time zone', DateTime(2026, 9, 28, 12, 30, 5)),
  ];

  for (final (name, palette) in [
    ('dark', darkPalette),
    ('light', lightPalette),
  ]) {
    for (final (dataType, value) in samples) {
      testWidgets('$dataType lays out in its size ($name)', (tester) async {
        AppColors.setPalette(palette);
        await _pumpPanel(
          tester,
          dataType: dataType,
          value: value,
          pending: const CellLiteral('x'),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Save'), findsOneWidget);
      });
    }
  }

  testWidgets('footer offers only the shortcuts the column allows', (
    tester,
  ) async {
    await _pumpPanel(
      tester,
      dataType: 'text',
      value: 'v',
      canBeNull: false,
      hasDefault: false,
    );
    expect(find.text('NULL'), findsNothing);
    expect(find.text('Default'), findsNothing);
    expect(find.text('Revert'), findsNothing);

    await _pumpPanel(
      tester,
      dataType: 'text',
      value: 'v',
      pending: const CellDefault(),
    );
    expect(find.text('NULL'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Revert'), findsOneWidget);
  });

  testWidgets('a boolean shows NULL once, in its strip', (tester) async {
    await _pumpPanel(tester, dataType: 'boolean', value: true);
    expect(find.text('NULL'), findsOneWidget);
  });
}
