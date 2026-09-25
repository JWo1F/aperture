import 'package:aperture/models/name_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('word initials find snake, kebab and camel case', () {
    expect(nameMatches('alice_bob', 'ab'), isTrue);
    expect(nameMatches('alice-bob', 'ab'), isTrue);
    expect(nameMatches('AliceBob', 'ab'), isTrue);
    expect(nameMatches('alice bob', 'AB'), isTrue);
  });

  test('word prefixes of any length combine', () {
    expect(nameMatches('alice_bob', 'albo'), isTrue);
    expect(nameMatches('order_line_items', 'ordli'), isTrue);
    expect(nameMatches('order_line_items', 'oi'), isTrue, reason: 'skips');
  });

  test('order matters and letters must start words', () {
    expect(nameMatches('alice_bob', 'ba'), isFalse);
    expect(nameMatches('alice_bob', 'lb'), isFalse);
    expect(nameMatches('alicebob', 'ab'), isFalse);
  });

  test('a substring still matches anywhere', () {
    expect(nameMatches('alice_bob', 'ce_b'), isTrue);
    expect(nameMatch('alice_bob', 'ice'), [2, 3, 4]);
  });

  test('offsets point at the matched letters', () {
    expect(nameMatch('alice_bob', 'ab'), [0, 6]);
    expect(nameMatch('AliceBob', 'albo'), [0, 1, 5, 6]);
    expect(nameMatch('alice_bob', 'zz'), isNull);
  });

  test('backtracks when the greedy prefix is wrong', () {
    // Greedy "ab" from "abc" would leave nothing for "bx".
    expect(nameMatches('abc_bxy', 'abx'), isTrue);
  });
}
