import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';
import '../formatters.dart';
import '../tz_input.dart';

class TimeBody extends StatelessWidget {
  const TimeBody({
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
  final void Function(int hour, int minute, int second, int ms) onChange;
  final ValueChanged<String> onTzChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TimeInput(
            key: ValueKey('time-$resetTick'),
            initial: initial,
            onChange: onChange,
          ),
          if (withTz) ...[
            const SizedBox(height: 10),
            TzInput(value: tz, onChange: onTzChange),
          ],
        ],
      ),
    );
  }
}

/// Four numeric fields HH : MM : SS . MS, value flows out via [onChange].
class _TimeInput extends StatefulWidget {
  const _TimeInput({super.key, required this.initial, required this.onChange});

  final DateTime initial;
  final void Function(int hour, int minute, int second, int ms) onChange;

  @override
  State<_TimeInput> createState() => _TimeInputState();
}

class _TimeInputState extends State<_TimeInput> {
  late final TextEditingController _h;
  late final TextEditingController _m;
  late final TextEditingController _s;
  late final TextEditingController _ms;

  @override
  void initState() {
    super.initState();
    _h = TextEditingController(text: pad2(widget.initial.hour));
    _m = TextEditingController(text: pad2(widget.initial.minute));
    _s = TextEditingController(text: pad2(widget.initial.second));
    _ms = TextEditingController(text: pad3(widget.initial.millisecond));
  }

  @override
  void dispose() {
    _h.dispose();
    _m.dispose();
    _s.dispose();
    _ms.dispose();
    super.dispose();
  }

  void _emit() {
    final h = (int.tryParse(_h.text) ?? 0).clamp(0, 23);
    final m = (int.tryParse(_m.text) ?? 0).clamp(0, 59);
    final s = (int.tryParse(_s.text) ?? 0).clamp(0, 59);
    final ms = (int.tryParse(_ms.text) ?? 0).clamp(0, 999);
    widget.onChange(h, m, s, ms);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _segment(_h, 'HH', width: 40, maxLen: 2),
        _sep(':'),
        _segment(_m, 'MM', width: 40, maxLen: 2),
        _sep(':'),
        _segment(_s, 'SS', width: 40, maxLen: 2),
        _sep('.'),
        _segment(_ms, 'MS', width: 50, maxLen: 3),
      ],
    );
  }

  Widget _segment(
    TextEditingController c,
    String hint, {
    required double width,
    required int maxLen,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: c,
        textAlign: TextAlign.center,
        cursorColor: AppColors.accent,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(maxLen),
        ],
        onChanged: (_) => _emit(),
        onSubmitted: (_) => _emit(),
        style: AppTheme.mono(size: 15, weight: FontWeight.w600),
        decoration: InputDecoration(
          isCollapsed: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
          hintText: hint,
          hintStyle: AppTheme.mono(size: 12, color: AppColors.textMuted),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: Radii.brSm,
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: Radii.brSm,
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: Radii.brSm,
            borderSide: BorderSide(color: AppColors.accent),
          ),
        ),
      ),
    );
  }

  Widget _sep(String c) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Text(c, style: AppTheme.mono(size: 15, color: AppColors.textMuted)),
  );
}
