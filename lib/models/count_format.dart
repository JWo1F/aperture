import 'db_object.dart';

/// Faint "rows / size" suffix for a table row, e.g. `110k / 10GB`. Returns
/// null when the engine reports neither figure.
String? tableStat(DbTable table) {
  final parts = <String>[
    if (table.rowEstimate != null) compactCount(table.rowEstimate!),
    if (table.sizeBytes != null) compactBytes(table.sizeBytes!),
  ];
  return parts.isEmpty ? null : parts.join(' / ');
}

/// `12,345`-style thousands grouping. Used wherever a raw count or row
/// estimate is shown in full precision (pagebars, query-plan metrics,
/// advice copy).
String withCommas(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Human-friendly row count: `940`, `1.2k`, `110k`, `3.4M`, `2.1B`.
String compactCount(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) {
    final k = n / 1000;
    return k >= 99.95 ? '${k.round()}k' : '${k.toStringAsFixed(1)}k';
  }
  if (n < 1000000000) {
    final m = n / 1000000;
    return m >= 99.95 ? '${m.round()}M' : '${m.toStringAsFixed(1)}M';
  }
  return '${(n / 1000000000).toStringAsFixed(1)}B';
}

/// Human-friendly byte size: `512B`, `48KB`, `10GB`, `1.4TB`.
String compactBytes(int bytes) {
  const kb = 1024.0;
  const mb = kb * 1024;
  const gb = mb * 1024;
  const tb = gb * 1024;
  if (bytes < kb) return '${bytes}B';
  if (bytes < mb) return '${(bytes / kb).round()}KB';
  if (bytes < gb) {
    final v = bytes / mb;
    return v >= 99.95 ? '${v.round()}MB' : '${v.toStringAsFixed(1)}MB';
  }
  if (bytes < tb) {
    final v = bytes / gb;
    return v >= 99.95 ? '${v.round()}GB' : '${v.toStringAsFixed(1)}GB';
  }
  return '${(bytes / tb).toStringAsFixed(1)}TB';
}
