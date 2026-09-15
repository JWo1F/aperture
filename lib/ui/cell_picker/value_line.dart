import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../theme/hugeicons.dart';
import '../widgets/common.dart';
import '../widgets/context_menu.dart';
import 'formatters.dart';
import 'kinds.dart';

/// Mono value line shown above date / time / datetime pickers — the design's
/// `.dt-valueline`, one tabular row showing the chosen moment in
/// `yyyy-mm-dd hh:mm:ss[@tz]` form with arrow-key bump on focused segments.
class MonoValueLine extends StatelessWidget {
  const MonoValueLine({
    super.key,
    required this.kind,
    required this.moment,
    required this.tz,
    required this.withTz,
    required this.onChange,
    required this.onTzChange,
  });

  final KindId kind;
  final DateTime moment;
  final String tz;
  final bool withTz;
  final ValueChanged<DateTime> onChange;
  final ValueChanged<String> onTzChange;

  void _setYear(int v) => onChange(moment.copyWith(year: v));
  void _setMonth(int v) => onChange(moment.copyWith(
    month: v,
    day: moment.day.clamp(1, daysInMonth(moment.year, v)),
  ));
  void _setDay(int v) => onChange(
    moment.copyWith(day: v.clamp(1, daysInMonth(moment.year, moment.month))),
  );
  void _setHour(int v) => onChange(moment.copyWith(hour: v));
  void _setMinute(int v) => onChange(moment.copyWith(minute: v));
  void _setSecond(int v) => onChange(moment.copyWith(second: v));

  @override
  Widget build(BuildContext context) {
    final hasDate = kind == KindId.date || kind == KindId.datetime;
    final hasTime = kind == KindId.time || kind == KindId.datetime;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          if (hasDate) ...[
            _Seg(
              value: moment.year,
              width: 44,
              padTo: 4,
              minValue: 1,
              maxValue: 9999,
              onChanged: _setYear,
            ),
            const _Punct('-'),
            _Seg(
              value: moment.month,
              width: 26,
              padTo: 2,
              minValue: 1,
              maxValue: 12,
              onChanged: _setMonth,
            ),
            const _Punct('-'),
            _Seg(
              value: moment.day,
              width: 26,
              padTo: 2,
              minValue: 1,
              maxValue: 31,
              onChanged: _setDay,
            ),
          ],
          if (hasDate && hasTime) const SizedBox(width: 12),
          if (hasTime) ...[
            _Seg(
              value: moment.hour,
              width: 26,
              padTo: 2,
              minValue: 0,
              maxValue: 23,
              onChanged: _setHour,
            ),
            const _Punct(':'),
            _Seg(
              value: moment.minute,
              width: 26,
              padTo: 2,
              minValue: 0,
              maxValue: 59,
              onChanged: _setMinute,
            ),
            const _Punct(':'),
            _Seg(
              value: moment.second,
              width: 26,
              padTo: 2,
              minValue: 0,
              maxValue: 59,
              onChanged: _setSecond,
            ),
          ],
          if (withTz && hasTime) ...[
            const _AtPunct(),
            _TzChip(value: tz, onChange: onTzChange),
          ],
        ],
      ),
    );
  }
}

/// A single digit field inside the mono value line — click to focus and type
/// (or paste) the new value. On blur or `Enter`, the entered number is
/// clamped to [[minValue], [maxValue]], re-padded to [padTo] digits, and
/// pushed back through [onChanged] so the parent's [DateTime] reconstruction
/// runs once with a known-good value.
class _Seg extends StatefulWidget {
  const _Seg({
    required this.value,
    required this.width,
    required this.padTo,
    required this.minValue,
    required this.maxValue,
    required this.onChanged,
  });

  final int value;
  final double width;
  final int padTo;
  final int minValue;
  final int maxValue;
  final ValueChanged<int> onChanged;

  @override
  State<_Seg> createState() => _SegState();
}

class _SegState extends State<_Seg> {
  late final TextEditingController _c;
  late final FocusNode _focus;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: _formatted(widget.value));
    _focus = FocusNode();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_Seg old) {
    super.didUpdateWidget(old);
    if (!_editing && old.value != widget.value) {
      _c.text = _formatted(widget.value);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _c.dispose();
    super.dispose();
  }

  String _formatted(int n) => n.toString().padLeft(widget.padTo, '0');

  void _onFocusChange() {
    if (!_focus.hasFocus && _editing) {
      _commit();
      setState(() => _editing = false);
    }
  }

  void _startEditing() {
    if (_editing) return;
    _c.text = _formatted(widget.value);
    setState(() => _editing = true);
    // The TextField is built next frame — request focus after it's mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      _c.selection = TextSelection(baseOffset: 0, extentOffset: _c.text.length);
    });
  }

  void _commit() {
    final raw = _c.text.trim();
    final parsed = int.tryParse(raw) ?? widget.value;
    final clamped = parsed.clamp(widget.minValue, widget.maxValue);
    if (clamped != widget.value) widget.onChanged(clamped);
    final padded = _formatted(clamped);
    if (_c.text != padded) _c.text = padded;
  }

  @override
  Widget build(BuildContext context) {
    // The mono value line is dense and the read-only path needs to be
    // pixel-perfect; rendering a TextField full-time fights Material's
    // internal layout (cursor reservation, scroll padding) and clips at
    // tight widths. Default to a plain Text and only swap to a TextField
    // while the user is actually editing.
    if (_editing) return _editor();
    return _readonly();
  }

  Widget _readonly() {
    return Hoverable(
      cursor: SystemMouseCursors.text,
      onTap: _startEditing,
      builder: (context, hovering) => Container(
        width: widget.width,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hovering ? AppColors.surfaceHover : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          _formatted(widget.value),
          style: AppTheme.mono(
            size: 14,
            color: AppColors.textPrimary,
            weight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _editor() {
    return Container(
      width: widget.width,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(3),
      ),
      child: EditableText(
        controller: _c,
        focusNode: _focus,
        autofocus: true,
        textAlign: TextAlign.center,
        cursorColor: AppColors.accent,
        backgroundCursorColor: AppColors.accent,
        keyboardType: TextInputType.number,
        scrollPhysics: const NeverScrollableScrollPhysics(),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(widget.padTo),
        ],
        onSubmitted: (_) {
          _commit();
          _focus.unfocus();
        },
        style: AppTheme.mono(
          size: 14,
          color: AppColors.textPrimary,
          weight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _Punct extends StatelessWidget {
  const _Punct(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Text(text, style: AppTheme.mono(size: 14, color: AppColors.text4)),
    );
  }
}

class _AtPunct extends StatelessWidget {
  const _AtPunct();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 6),
      child: Text('@', style: AppTheme.mono(size: 14, color: AppColors.text4)),
    );
  }
}

class _TzChip extends StatelessWidget {
  const _TzChip({required this.value, required this.onChange});

  final String value;
  final ValueChanged<String> onChange;

  static const _options = [
    ('-08', 'PST'),
    ('-07', 'PDT/MST'),
    ('-05', 'EST'),
    ('+00', 'UTC'),
    ('+01', 'CET'),
    ('+05:30', 'IST'),
    ('+09', 'JST'),
  ];

  void _open(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset(0, box.size.height + 4));
    showContextMenu(
      context,
      globalPosition: origin,
      entries: [
        for (final (tz, lbl) in _options)
          CmItem(
            label: tz,
            shortcut: lbl,
            icon: tz == value ? Hgi.tick02 : null,
            onTap: () => onChange(tz),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final display = value.trim().isEmpty ? '+00' : value;
    return Builder(
      builder: (context) => Hoverable(
        cursor: SystemMouseCursors.click,
        onTap: () => _open(context),
        builder: (context, hovering) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: hovering ? AppColors.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                display,
                style: AppTheme.mono(size: 14, color: AppColors.accent),
              ),
              const SizedBox(width: 3),
              Icon(Hgi.arrowDown01, size: 10, color: AppColors.text4),
            ],
          ),
        ),
      ),
    );
  }
}
