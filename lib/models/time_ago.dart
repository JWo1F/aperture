/// Filesystem-safe ISO-ish timestamp suitable for export filenames:
/// `2026-05-20T14-32-10` (no colons, no fractional seconds).
String filenameTimestamp([DateTime? now]) => (now ?? DateTime.now())
    .toIso8601String()
    .replaceAll(':', '-')
    .split('.')
    .first;

/// Compact relative-time formatter ("3m ago", "yesterday", "5d ago").
String timeAgo(DateTime when, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(when);

  if (diff.isNegative) return 'just now';
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 2) return '1 min ago';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 2) return '1 hr ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  if (diff.inDays < 30) return '${diff.inDays ~/ 7}w ago';
  if (diff.inDays < 365) return '${diff.inDays ~/ 30}mo ago';
  return '${diff.inDays ~/ 365}y ago';
}
