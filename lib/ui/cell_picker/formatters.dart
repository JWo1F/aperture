String pad2(int n) => n.toString().padLeft(2, '0');

String pad3(int n) => n.toString().padLeft(3, '0');

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

extension DateTimeCopy on DateTime {
  DateTime copyWith({
    int? year,
    int? month,
    int? day,
    int? hour,
    int? minute,
    int? second,
    int? millisecond,
  }) => DateTime(
    year ?? this.year,
    month ?? this.month,
    day ?? this.day,
    hour ?? this.hour,
    minute ?? this.minute,
    second ?? this.second,
    millisecond ?? this.millisecond,
  );
}

String formatDate(DateTime d) => '${d.year}-${pad2(d.month)}-${pad2(d.day)}';

String formatTime(DateTime d, {String? tz}) {
  final base =
      '${pad2(d.hour)}:${pad2(d.minute)}:${pad2(d.second)}'
      '.${pad3(d.millisecond)}';
  final t = tz?.trim() ?? '';
  return t.isEmpty ? base : '$base $t';
}

String formatDateTime(DateTime d, {String? tz}) =>
    '${formatDate(d)} ${formatTime(d, tz: tz)}';
