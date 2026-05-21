import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../tz_input.dart';
import 'calendar_body.dart';

class DateTimeBody extends StatefulWidget {
  const DateTimeBody({
    super.key,
    required this.initial,
    required this.withTz,
    required this.tz,
    required this.resetTick,
    required this.onChange,
    required this.onTzChange,
  });

  final DateTime initial;
  final bool withTz;
  final String tz;
  final int resetTick;
  final ValueChanged<DateTime> onChange;
  final ValueChanged<String> onTzChange;

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
    // Hours/minutes/seconds are edited via the arrow-key segments in the
    // MonoValueLine above this body, so the body itself only carries the
    // calendar (plus an optional TZ input — kept here because the value line
    // surfaces TZ as a small chip rather than an editable text field).
    return Container(
      color: AppColors.bg,
      child: Column(
        children: [
          Expanded(
            child: CalendarGrid(
              key: ValueKey('cal-${widget.resetTick}'),
              initial: _value,
              onChange: _setDate,
            ),
          ),
          if (widget.withTz) ...[
            Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: TzInput(value: widget.tz, onChange: widget.onTzChange),
            ),
          ],
        ],
      ),
    );
  }
}
