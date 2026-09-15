import 'package:aperture/models/cell_edit.dart';
import 'package:aperture/ui/workspace/results_grid/grid_slots.dart';
import 'package:flutter_test/flutter_test.dart';

/// `(isInsert, sourceIdx)` for each slot — the mapping every "row index" in
/// the grid is resolved through.
List<(bool, int)> _shape(List<Slot> slots) =>
    [for (final s in slots) (s.isInsert, s.sourceIdx)];

PendingInsert _insert({int? afterRow}) => PendingInsert(afterRow: afterRow);

void main() {
  group('buildSlots', () {
    test('with no inserts the mapping is the identity', () {
      expect(_shape(buildSlots(3, null)), [
        (false, 0),
        (false, 1),
        (false, 2),
      ]);
      expect(_shape(buildSlots(2, const [])), [(false, 0), (false, 1)]);
    });

    test('no rows and no inserts is empty', () {
      expect(buildSlots(0, null), isEmpty);
    });

    test('an anchored insert renders immediately after its row', () {
      final slots = buildSlots(3, [_insert(afterRow: 1)]);
      expect(_shape(slots), [
        (false, 0),
        (false, 1),
        (true, 0),
        (false, 2),
      ]);
    });

    test('an unanchored insert is appended', () {
      final slots = buildSlots(2, [_insert()]);
      expect(_shape(slots), [(false, 0), (false, 1), (true, 0)]);
    });

    test('a stale anchor is appended, never dropped', () {
      // Pending inserts deliberately survive a page change, so an
      // `afterRow` can point past the new result. Losing the insert would
      // lose a row the user queued.
      final slots = buildSlots(2, [_insert(afterRow: 99)]);
      expect(_shape(slots), [(false, 0), (false, 1), (true, 0)]);
    });

    test('a negative anchor is treated as unanchored', () {
      final slots = buildSlots(1, [_insert(afterRow: -1)]);
      expect(_shape(slots), [(false, 0), (true, 0)]);
    });

    test('two inserts on the same row keep their insertion order', () {
      final slots = buildSlots(2, [
        _insert(afterRow: 0),
        _insert(afterRow: 0),
      ]);
      expect(_shape(slots), [
        (false, 0),
        (true, 0),
        (true, 1),
        (false, 1),
      ]);
    });

    test('anchored and unanchored inserts coexist in one pass', () {
      final slots = buildSlots(2, [
        _insert(afterRow: 1),
        _insert(),
        _insert(afterRow: 0),
      ]);
      expect(_shape(slots), [
        (false, 0),
        (true, 2),
        (false, 1),
        (true, 0),
        (true, 1),
      ]);
    });

    test('inserts against an empty result all land at the end', () {
      final slots = buildSlots(0, [_insert(afterRow: 0), _insert()]);
      expect(_shape(slots), [(true, 0), (true, 1)]);
    });

    test('every slot index is addressable and unique', () {
      final slots = buildSlots(3, [
        _insert(afterRow: 0),
        _insert(afterRow: 2),
        _insert(),
      ]);
      expect(slots, hasLength(6));
      final persistent = slots.where((s) => !s.isInsert).map((s) => s.sourceIdx);
      final inserts = slots.where((s) => s.isInsert).map((s) => s.sourceIdx);
      expect(persistent.toSet(), {0, 1, 2});
      expect(inserts.toSet(), {0, 1, 2});
    });
  });
}
