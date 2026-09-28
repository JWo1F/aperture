import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import '../../widgets/common.dart';

class CalendarBody extends StatefulWidget {
  const CalendarBody({
    super.key,
    required this.initial,
    required this.resetTick,
    required this.onChange,
  });

  final DateTime initial;
  final int resetTick;
  final ValueChanged<DateTime> onChange;

  @override
  State<CalendarBody> createState() => _CalendarBodyState();
}

class _CalendarBodyState extends State<CalendarBody> {
  late DateTime _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initial;
  }

  @override
  void didUpdateWidget(CalendarBody old) {
    super.didUpdateWidget(old);
    if (old.resetTick != widget.resetTick) {
      _current = widget.initial;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CalendarGrid(
      key: ValueKey('cal-${widget.resetTick}'),
      initial: _current,
      onChange: (d) {
        setState(() => _current = d);
        widget.onChange(d);
      },
    );
  }
}

/// Month grid: the selected day is a filled accent tile, today is drawn in
/// the accent. Exposed so DateTimeBody can embed it directly without going
/// through CalendarBody's resetTick gating.
class CalendarGrid extends StatefulWidget {
  const CalendarGrid({
    super.key,
    required this.initial,
    required this.onChange,
  });

  final DateTime initial;
  final ValueChanged<DateTime> onChange;

  @override
  State<CalendarGrid> createState() => _CalendarGridState();
}

class _CalendarGridState extends State<CalendarGrid> {
  late int _vy;
  late int _vm;

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    _vy = widget.initial.year;
    _vm = widget.initial.month;
  }

  @override
  void didUpdateWidget(CalendarGrid old) {
    super.didUpdateWidget(old);
    if (old.initial != widget.initial) {
      _vy = widget.initial.year;
      _vm = widget.initial.month;
    }
  }

  int _daysInMonth(int y, int m) => DateTime(y, m + 1, 0).day;

  int _firstDow(int y, int m) => DateTime(y, m, 1).weekday % 7;

  void _prev() {
    setState(() {
      if (_vm == 1) {
        _vm = 12;
        _vy -= 1;
      } else {
        _vm -= 1;
      }
    });
  }

  void _next() {
    setState(() {
      if (_vm == 12) {
        _vm = 1;
        _vy += 1;
      } else {
        _vm += 1;
      }
    });
  }

  void _jumpToday() {
    final now = DateTime.now();
    setState(() {
      _vy = now.year;
      _vm = now.month;
    });
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final nDays = _daysInMonth(_vy, _vm);
    final lead = _firstDow(_vy, _vm);
    final trail = 42 - lead - nDays;
    final prevDays = _vm == 1
        ? _daysInMonth(_vy - 1, 12)
        : _daysInMonth(_vy, _vm - 1);

    final cells = <_CalCell>[];
    for (var i = lead - 1; i >= 0; i--) {
      cells.add(_CalCell(day: prevDays - i, outside: true, next: false));
    }
    for (var d = 1; d <= nDays; d++) {
      cells.add(_CalCell(day: d, outside: false, next: false));
    }
    for (var d = 1; d <= trail; d++) {
      cells.add(_CalCell(day: d, outside: true, next: true));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [_header(), _dow(), _grid(cells, today)],
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 6, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_months[_vm - 1]} $_vy',
              style: AppTheme.ui(size: 12, weight: FontWeight.w600),
            ),
          ),
          _navBtn(Hgi.chevronLeft, _prev, 'Previous month'),
          _navBtn(Hgi.record, _jumpToday, 'Current month'),
          _navBtn(Hgi.chevronRight, _next, 'Next month'),
        ],
      ),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback onTap, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: Hoverable(
        onTap: onTap,
        builder: (context, hovering) => Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovering
                ? AppColors.surfaceHover
                : AppColors.surfaceHover.withValues(alpha: 0),
            borderRadius: Radii.brSm,
          ),
          child: Icon(
            icon,
            size: icon == Hgi.record ? 7 : 13,
            color: hovering ? AppColors.textPrimary : AppColors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _dow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (final l in const ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'])
            Expanded(
              child: SizedBox(
                height: 18,
                child: Center(
                  child: Text(
                    l,
                    style: AppTheme.ui(size: 10, color: AppColors.text4),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _grid(List<_CalCell> cells, DateTime today) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < 6; r++)
            Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(child: _cellWidget(cells[r * 7 + c], today)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cellWidget(_CalCell cell, DateTime today) {
    final isToday =
        !cell.outside &&
        cell.day == today.day &&
        _vm == today.month &&
        _vy == today.year;
    final isSel =
        !cell.outside &&
        cell.day == widget.initial.day &&
        _vm == widget.initial.month &&
        _vy == widget.initial.year;

    return Hoverable(
      onTap: () {
        final ny = cell.next
            ? (_vm == 12 ? _vy + 1 : _vy)
            : cell.outside
            ? (_vm == 1 ? _vy - 1 : _vy)
            : _vy;
        final nm = cell.next
            ? (_vm == 12 ? 1 : _vm + 1)
            : cell.outside
            ? (_vm == 1 ? 12 : _vm - 1)
            : _vm;
        widget.onChange(
          DateTime(
            ny,
            nm,
            cell.day,
            widget.initial.hour,
            widget.initial.minute,
            widget.initial.second,
            widget.initial.millisecond,
          ),
        );
        setState(() {
          _vy = ny;
          _vm = nm;
        });
      },
      builder: (context, hovering) {
        final Color bg = isSel
            ? AppColors.accent
            : (hovering
                  ? AppColors.surfaceHover
                  : AppColors.surfaceHover.withValues(alpha: 0));
        final Color fg = isSel
            ? Colors.white
            : cell.outside
            ? AppColors.text4
            : (isToday ? AppColors.accent : AppColors.textSecondary);
        return Container(
          height: 24,
          margin: const EdgeInsets.all(1),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, borderRadius: Radii.brSm),
          child: Text(
            '${cell.day}',
            style: AppTheme.mono(
              size: 11.5,
              color: fg,
              weight: FontWeight.w500,
            ),
          ),
        );
      },
    );
  }
}

class _CalCell {
  const _CalCell({
    required this.day,
    required this.outside,
    required this.next,
  });

  final int day;
  final bool outside;
  final bool next;
}
