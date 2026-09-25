/// Where [query] matches [name], as the character offsets it covers, or
/// null when it doesn't. Case-insensitive; [query] is expected trimmed.
///
/// A plain substring match wins. Otherwise the query may be spelled as
/// prefixes of the name's words, in order and skipping words freely — so
/// `ab` finds `alice_bob`, `alice-bob` and `AliceBob`, and `albo` finds
/// `alice_bob`. Words split on anything that isn't a letter or digit, and
/// where lower case turns to upper.
List<int>? nameMatch(String name, String query) {
  if (query.isEmpty) return const [];
  final lowerName = name.toLowerCase();
  final q = query.toLowerCase();
  final at = lowerName.indexOf(q);
  if (at >= 0) return [for (var i = at; i < at + q.length; i++) i];

  final words = _words(name);
  if (words.isEmpty) return null;
  final failed = <(int, int)>{};

  // Consumes q from [qi] using words from [wi] on; returns offsets or null.
  List<int>? from(int qi, int wi) {
    if (qi == q.length) return const [];
    if (failed.contains((qi, wi))) return null;
    for (var k = wi; k < words.length; k++) {
      final (start, end) = words[k];
      final maxLen = (end - start).clamp(0, q.length - qi);
      for (var len = maxLen; len > 0; len--) {
        if (lowerName.startsWith(q.substring(qi, qi + len), start)) {
          final rest = from(qi + len, k + 1);
          if (rest != null) {
            return [for (var i = start; i < start + len; i++) i, ...rest];
          }
        }
      }
    }
    failed.add((qi, wi));
    return null;
  }

  return from(0, 0);
}

bool nameMatches(String name, String query) => nameMatch(name, query) != null;

final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _upper = RegExp(r'\p{Lu}', unicode: true);
final _lower = RegExp(r'\p{Ll}', unicode: true);

/// `[start, end)` spans of the words in [name].
List<(int, int)> _words(String name) {
  final out = <(int, int)>[];
  int? start;
  for (var i = 0; i < name.length; i++) {
    final c = name[i];
    if (!_letterOrDigit.hasMatch(c)) {
      if (start != null) out.add((start, i));
      start = null;
      continue;
    }
    final camelBreak =
        start != null && _upper.hasMatch(c) && _lower.hasMatch(name[i - 1]);
    if (camelBreak) {
      out.add((start, i));
      start = i;
    }
    start ??= i;
  }
  if (start != null) out.add((start, name.length));
  return out;
}
