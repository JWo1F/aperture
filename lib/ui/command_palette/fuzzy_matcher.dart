import 'item_model.dart';

class FuzzyMatch {
  const FuzzyMatch(this.score, this.indices);

  final int score;
  final List<int> indices;
}

/// Word-boundary-aware fuzzy subsequence matcher.
///
/// Finds the best-scoring way to match every character of [query] against
/// [text] in order. Returns null when [query] is not a subsequence of
/// [text]. A match that lands on word starts (`users` in `app_users`) and
/// runs contiguously outscores one whose characters are scattered, so the
/// ranking promotes the result a human would point at.
FuzzyMatch? fuzzyMatch(String query, String text) {
  if (query.isEmpty) return const FuzzyMatch(0, <int>[]);
  final q = query.toLowerCase();
  final t = text.toLowerCase();
  if (q.length > t.length) return null;

  bool boundary(int i) {
    if (i == 0) return true;
    final prev = text.codeUnitAt(i - 1);
    // Separators that begin a new word.
    if (prev == 0x20 || prev == 0x5F || prev == 0x2E ||
        prev == 0x2D || prev == 0x2F) {
      return true;
    }
    // camelCase / digit→letter boundary.
    final cur = text.codeUnitAt(i);
    final prevWord = (prev >= 0x61 && prev <= 0x7A) ||
        (prev >= 0x30 && prev <= 0x39);
    final curUpper = cur >= 0x41 && cur <= 0x5A;
    return prevWord && curUpper;
  }

  final stride = t.length + 1;
  final memo = <int, FuzzyMatch?>{};

  // Best match of q[qi..] against t[ti..]. Memoised on (qi, ti) so the
  // branch-and-explore stays linear in the size of the DP table.
  FuzzyMatch? solve(int qi, int ti) {
    if (qi == q.length) return const FuzzyMatch(0, <int>[]);
    if (ti >= t.length) return null;
    final key = qi * stride + ti;
    if (memo.containsKey(key)) return memo[key];

    FuzzyMatch? best;
    for (var i = ti; i < t.length; i++) {
      if (t.codeUnitAt(i) != q.codeUnitAt(qi)) continue;
      final rest = solve(qi + 1, i + 1);
      if (rest == null) continue;
      var gain = 1;
      if (boundary(i)) gain += 12;
      if (i == 0) gain += 8;
      if (rest.indices.isNotEmpty && rest.indices.first == i + 1) gain += 10;
      // Penalise characters skipped before the very first match.
      if (qi == 0 && i > 0) gain -= i > 6 ? 6 : i;
      final score = gain + rest.score;
      if (best == null || score > best.score) {
        best = FuzzyMatch(score, <int>[i, ...rest.indices]);
      }
    }
    memo[key] = best;
    return best;
  }

  return solve(0, 0);
}

/// Scores [item] against [query]. A title hit always beats a hit found only
/// in the hidden haystack, which keeps "users" ranking the `users` table
/// above a table whose comment merely mentions users.
///
/// On top of the raw fuzzy score, three bonuses keep the obvious answer on
/// top: an exact name match wins outright, a prefix match is strongly
/// promoted, and a coverage term rewards matching a large fraction of the
/// name — so the short `users` outranks the long `user_notification_settings`
/// even though the latter's characters happen to land on word boundaries.
PaletteHit? scoreItem(PaletteItem item, String query) {
  final q = query.toLowerCase();
  final title = fuzzyMatch(query, item.title);
  if (title != null) {
    var score = title.score + item.kind.bias;
    final name = item.title.toLowerCase();
    if (name == q) {
      score += 120;
    } else if (name.startsWith(q)) {
      score += 45;
    }
    score += 20 * (q.length / item.title.length);
    return PaletteHit(item, score, title.indices);
  }
  final aux = fuzzyMatch(query, item.haystack);
  if (aux != null) {
    return PaletteHit(item, aux.score * 0.45 + item.kind.bias, const []);
  }
  return null;
}
