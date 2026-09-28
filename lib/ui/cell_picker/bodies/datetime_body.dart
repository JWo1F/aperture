import 'package:flutter/material.dart';

import 'calendar_body.dart';

/// Only the calendar: hours, minutes, seconds and the zone are edited in
/// the value line above.
class DateTimeBody extends StatefulWidget {
  const DateTimeBody({
    super.key,
    required this.initial,
    required this.resetTick,
    required this.onChange,
  });

  final DateTime initial;
  final int resetTick;
  final ValueChanged<DateTime> onChange;

  @override
  State<DateTimeBody> createState() => _DateTimeBodyState();
}

class _DateTimeBodyState extends State<DateTimeBody> {
  late DateTime _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
  }

  @override
  void didUpdateWidget(DateTimeBody old) {
    super.didUpdateWidget(old);
    if (old.resetTick != widget.resetTick) {
      _value = widget.initial;
    }
  }

  void _setDate(DateTime d) {
    final next = DateTime(
      d.year,
      d.month,
      d.day,
      _value.hour,
      _value.minute,
      _value.second,
      _value.millisecond,
    );
    setState(() => _value = next);
    widget.onChange(next);
  }

  @override
  Widget build(BuildContext context) {
    return CalendarGrid(
      key: ValueKey('cal-${widget.resetTick}'),
      initial: _value,
      onChange: _setDate,
    );
  }
}
