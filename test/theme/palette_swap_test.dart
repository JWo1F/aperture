import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/ui/cell_picker/kinds.dart';
import 'package:aperture/ui/workspace/results_grid/cell_content.dart';
import 'package:aperture/ui/workspace/results_grid/format_cache.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Values captured in a top-level `final` are resolved once per process, so a
/// palette-derived colour stored that way survives a dark ⇄ light swap and
/// paints the wrong theme's tone for the rest of the session.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AppColors.setPalette(darkPalette));

  test('a cell-picker kind colour follows a palette swap', () {
    AppColors.setPalette(darkPalette);
    final dark = kindFor(true, 'boolean').color;
    AppColors.setPalette(lightPalette);
    final light = kindFor(true, 'boolean').color;

    expect(dark, darkPalette.tBool);
    expect(light, lightPalette.tBool);
  });

  test('a NULL grid cell follows a palette swap', () {
    InlineSpan nullSpan() => gridCellSpan(
      pending: null,
      isInsert: false,
      sourceIdx: 0,
      column: 0,
      original: null,
      formatCache: FormatCache(),
      dataType: 'text',
    );

    AppColors.setPalette(darkPalette);
    final dark = nullSpan().style?.color;
    AppColors.setPalette(lightPalette);
    final light = nullSpan().style?.color;

    expect(dark, isNotNull);
    expect(
      light,
      isNot(dark),
      reason: 'NULL cells would keep the previous theme\'s muted tone',
    );
  });
}
