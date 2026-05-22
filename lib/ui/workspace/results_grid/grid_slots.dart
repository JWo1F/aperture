import '../../../models/cell_edit.dart';

/// One slot in the visual row order — either a persistent row (index into
/// `result.rows`) or a pending insert (index into the inserts list). The
/// rest of the grid treats row indexing as a single linear axis over slots.
class Slot {
  const Slot.persistent(this.sourceIdx) : isInsert = false;
  const Slot.insert(this.sourceIdx) : isInsert = true;

  final bool isInsert;
  final int sourceIdx;
}

/// Interleaved render order: each persistent row, followed by every pending
/// insert anchored to it, with un-anchored inserts appended at the end.
List<Slot> buildSlots(int persistentRowCount, List<PendingInsert>? inserts) {
  if (inserts == null || inserts.isEmpty) {
    return [for (var r = 0; r < persistentRowCount; r++) Slot.persistent(r)];
  }
  final anchored = <int, List<int>>{};
  final unanchored = <int>[];
  for (var i = 0; i < inserts.length; i++) {
    final after = inserts[i].afterRow;
    if (after != null && after >= 0 && after < persistentRowCount) {
      anchored.putIfAbsent(after, () => <int>[]).add(i);
    } else {
      unanchored.add(i);
    }
  }
  final out = <Slot>[];
  for (var r = 0; r < persistentRowCount; r++) {
    out.add(Slot.persistent(r));
    final group = anchored[r];
    if (group != null) {
      for (final i in group) {
        out.add(Slot.insert(i));
      }
    }
  }
  for (final i in unanchored) {
    out.add(Slot.insert(i));
  }
  return out;
}
