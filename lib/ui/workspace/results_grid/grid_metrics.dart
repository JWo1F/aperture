import 'package:flutter/widgets.dart';

import '../../../theme/app_theme.dart';

/// Shared geometry and text styles for the results-grid modules.

const double kRowHeight = 26;

/// Width of the pinned row-number gutter. Matches the WHERE / SELECT / ORDER
/// label column in the clause bar so the grid aligns with the clauses above.
const double kIndexWidth = 64;

/// Hit-target width of a header column's resize handle.
const double kResizeHandleWidth = 7;

/// Whitespace reserved at the bottom of the scrollable body so the horizontal
/// scrollbar thumb sits in a gutter rather than overlaying the last row. Both
/// the data ListView and the IndexColumn ListView apply this — without that,
/// the index rail (driven by a follower controller) clamps short of the
/// data list's max scroll extent and the rows drift out of alignment.
const double kGridBottomGutter = 12;

/// Base style for data cells — also the input style `jsonSpans` highlights
/// against, so the highlighted and plain branches share one metric.
final TextStyle gridCellStyle = AppTheme.mono(size: 11.5);

final TextStyle gridNullStyle = AppTheme.mono(
  size: 11.5,
  color: AppColors.textMuted,
).copyWith(fontStyle: FontStyle.italic);
