import 'package:aperture/models/count_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatRunElapsed', () {
    test('sub-minute values carry one floored decimal', () {
      expect(formatRunElapsed(const Duration(milliseconds: 0)), '0.0s');
      expect(formatRunElapsed(const Duration(milliseconds: 412)), '0.4s');
      expect(formatRunElapsed(const Duration(milliseconds: 12700)), '12.7s');
      expect(formatRunElapsed(const Duration(milliseconds: 59999)), '59.9s');
    });

    test('a minute or more switches to m/s with a padded seconds field', () {
      expect(formatRunElapsed(const Duration(seconds: 60)), '1m 00s');
      expect(formatRunElapsed(const Duration(seconds: 64)), '1m 04s');
      expect(formatRunElapsed(const Duration(seconds: 3599)), '59m 59s');
    });

    test('an hour or more switches to h/m', () {
      expect(formatRunElapsed(const Duration(hours: 1)), '1h 00m');
      expect(
        formatRunElapsed(const Duration(hours: 2, minutes: 4)),
        '2h 04m',
      );
    });

    test('a negative duration clamps to zero rather than printing a sign', () {
      expect(formatRunElapsed(const Duration(milliseconds: -50)), '0.0s');
    });
  });
}
