import 'package:aperture/models/order_term.dart';
import 'package:flutter_test/flutter_test.dart';

List<(String, bool)> _pairs(List<OrderTerm> terms) =>
    [for (final t in terms) (t.column, t.descending)];

void main() {
  group('parseOrderBy', () {
    test('a bare column is ascending', () {
      expect(_pairs(parseOrderBy('name')), [('name', false)]);
    });

    test('quotes are stripped and direction read', () {
      expect(
        _pairs(parseOrderBy('"name" DESC, id')),
        [('name', true), ('id', false)],
      );
    });

    test('direction keywords are case-insensitive', () {
      expect(_pairs(parseOrderBy('a desc')), [('a', true)]);
      expect(_pairs(parseOrderBy('a Desc')), [('a', true)]);
      expect(_pairs(parseOrderBy('a ASC')), [('a', false)]);
      expect(_pairs(parseOrderBy('a asc')), [('a', false)]);
    });

    test('an expression keeps its inner spaces', () {
      expect(_pairs(parseOrderBy('lower(name) desc')), [
        ('lower(name)', true),
      ]);
      expect(_pairs(parseOrderBy('a + b')), [('a + b', false)]);
    });

    test('empty and whitespace-only input yields nothing', () {
      expect(parseOrderBy(''), isEmpty);
      expect(parseOrderBy('   '), isEmpty);
      expect(parseOrderBy(' , , '), isEmpty);
    });

    test('a trailing comma does not produce a blank term', () {
      expect(_pairs(parseOrderBy('a, b,')), [('a', false), ('b', false)]);
    });
  });

  group('renderOrderBy', () {
    test('quotes a plain identifier and always states the direction', () {
      expect(
        renderOrderBy(const [OrderTerm('name', true)]),
        '"name" DESC',
      );
      expect(renderOrderBy(const [OrderTerm('id', false)]), '"id" ASC');
    });

    test('leaves an expression unquoted', () {
      expect(
        renderOrderBy(const [OrderTerm('lower(name)', false)]),
        'lower(name) ASC',
      );
    });

    test('joins multiple terms in order', () {
      expect(
        renderOrderBy(const [OrderTerm('a', false), OrderTerm('b', true)]),
        '"a" ASC, "b" DESC',
      );
    });

    test('no terms renders empty', () {
      expect(renderOrderBy(const []), '');
    });
  });

  group('round-trip', () {
    test('render then parse then render is stable', () {
      // Header clicks run this loop repeatedly; a shape that drifted would
      // mangle the clause a little more on every click.
      for (final raw in [
        'name',
        '"name" DESC',
        '"a" ASC, "b" DESC',
        'lower(name) DESC',
      ]) {
        final once = renderOrderBy(parseOrderBy(raw));
        final twice = renderOrderBy(parseOrderBy(once));
        expect(twice, once, reason: raw);
      }
    });
  });

  group('cycleOrder', () {
    test('walks absent → ASC → DESC → absent', () {
      var terms = <OrderTerm>[];
      terms = cycleOrder(terms, 'a');
      expect(_pairs(terms), [('a', false)]);
      terms = cycleOrder(terms, 'a');
      expect(_pairs(terms), [('a', true)]);
      terms = cycleOrder(terms, 'a');
      expect(terms, isEmpty);
    });

    test('other columns keep their position and direction', () {
      final terms = cycleOrder(
        const [OrderTerm('a', true), OrderTerm('b', false)],
        'b',
      );
      expect(_pairs(terms), [('a', true), ('b', true)]);
    });

    test('removing a middle column leaves the rest in order', () {
      final terms = cycleOrder(
        const [
          OrderTerm('a', false),
          OrderTerm('b', true),
          OrderTerm('c', false),
        ],
        'b',
      );
      expect(_pairs(terms), [('a', false), ('c', false)]);
    });

    test('does not mutate the list it was given', () {
      final original = <OrderTerm>[const OrderTerm('a', false)];
      cycleOrder(original, 'a');
      cycleOrder(original, 'b');
      expect(_pairs(original), [('a', false)]);
    });

    test('a new column is appended last, not prepended', () {
      final terms = cycleOrder(const [OrderTerm('a', false)], 'b');
      expect(_pairs(terms), [('a', false), ('b', false)]);
    });
  });
}
