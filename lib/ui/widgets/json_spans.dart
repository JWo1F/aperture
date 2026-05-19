import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';

/// Tokenises an already-encoded JSON string into coloured [TextSpan]s.
///
/// Cheap, single-pass, no allocations beyond the spans themselves. Designed
/// to render inline inside a grid cell with `maxLines: 1` ellipsis.
List<InlineSpan> jsonSpans(String source, TextStyle base) {
  final spans = <InlineSpan>[];
  if (source.isEmpty) return spans;

  final length = source.length;
  var i = 0;

  TextStyle styled(Color color) => base.copyWith(color: color);

  while (i < length) {
    final ch = source.codeUnitAt(i);

    // Strings — quoted, with backslash escape.
    if (ch == 0x22 /* " */) {
      final start = i;
      i++;
      while (i < length) {
        final c = source.codeUnitAt(i);
        if (c == 0x5C /* \ */) {
          i += 2;
          continue;
        }
        i++;
        if (c == 0x22) break;
      }
      // Look past whitespace for ':' to decide key vs value.
      var j = i;
      while (j < length && source.codeUnitAt(j) == 0x20) {
        j++;
      }
      final isKey = j < length && source.codeUnitAt(j) == 0x3A /* : */;
      spans.add(TextSpan(
        text: source.substring(start, i),
        style: styled(
          isKey ? AppColors.sqlKeyword : AppColors.sqlString,
        ),
      ));
      continue;
    }

    // Numbers — optional minus, digits, optional fraction, optional exponent.
    if (ch == 0x2D /* - */ || (ch >= 0x30 && ch <= 0x39)) {
      final start = i;
      i++;
      while (i < length) {
        final c = source.codeUnitAt(i);
        final isDigit = c >= 0x30 && c <= 0x39;
        final isDecimalish = c == 0x2E || c == 0x65 || c == 0x45 ||
            c == 0x2B || c == 0x2D;
        if (!isDigit && !isDecimalish) break;
        i++;
      }
      spans.add(TextSpan(
        text: source.substring(start, i),
        style: styled(AppColors.sqlNumber),
      ));
      continue;
    }

    // Keywords: true / false / null
    if (_match(source, i, 'true')) {
      spans.add(TextSpan(text: 'true', style: styled(AppColors.sqlFunction)));
      i += 4;
      continue;
    }
    if (_match(source, i, 'false')) {
      spans.add(TextSpan(text: 'false', style: styled(AppColors.sqlFunction)));
      i += 5;
      continue;
    }
    if (_match(source, i, 'null')) {
      spans.add(TextSpan(text: 'null', style: styled(AppColors.textMuted)));
      i += 4;
      continue;
    }

    // Structural / whitespace — accumulate as much as possible in one span.
    final start = i;
    i++;
    while (i < length) {
      final c = source.codeUnitAt(i);
      if (c == 0x22 ||
          c == 0x2D ||
          (c >= 0x30 && c <= 0x39) ||
          c == 0x74 ||
          c == 0x66 ||
          c == 0x6E) {
        break;
      }
      i++;
    }
    spans.add(TextSpan(
      text: source.substring(start, i),
      style: styled(AppColors.textSecondary),
    ));
  }

  return spans;
}

bool _match(String source, int offset, String literal) {
  if (offset + literal.length > source.length) return false;
  for (var k = 0; k < literal.length; k++) {
    if (source.codeUnitAt(offset + k) != literal.codeUnitAt(k)) return false;
  }
  return true;
}
