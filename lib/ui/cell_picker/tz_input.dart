import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/hugeicons.dart';
import '../widgets/common.dart';
import '../widgets/context_menu.dart';

/// Inline timezone field for the value line: free text (`UTC`, `+02:00`,
/// `Europe/Berlin`, …) plus a chevron with common offsets. Empty means no
/// zone is written, so the server applies the session's.
class TzField extends StatefulWidget {
  const TzField({super.key, required this.value, required this.onChange});

  final String value;
  final ValueChanged<String> onChange;

  @override
  State<TzField> createState() => _TzFieldState();
}

class _TzFieldState extends State<TzField> {
  late final TextEditingController _c;

  static const _presets = [
    ('-08', 'PST'),
    ('-07', 'PDT/MST'),
    ('-05', 'EST'),
    ('+00', 'UTC'),
    ('+01', 'CET'),
    ('+05:30', 'IST'),
    ('+09', 'JST'),
  ];

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(TzField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _c.text != widget.value) {
      _c.text = widget.value;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _openPresets(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    showContextMenu(
      context,
      globalPosition: box.localToGlobal(Offset(0, box.size.height + 4)),
      entries: [
        for (final (tz, label) in _presets)
          CmItem(
            label: tz,
            shortcut: label,
            icon: tz == widget.value ? Hgi.tick02 : null,
            onTap: () => widget.onChange(tz),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 24,
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: Radii.brSm,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _c,
              cursorColor: AppColors.accent,
              onChanged: widget.onChange,
              style: AppTheme.mono(size: 12, color: AppColors.accent),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'session',
                hintStyle: AppTheme.ui(size: 11, color: AppColors.text4),
                contentPadding: const EdgeInsets.only(left: 6, top: 4),
              ),
            ),
          ),
          Builder(
            builder: (context) => Hoverable(
              onTap: () => _openPresets(context),
              builder: (context, hovering) => Container(
                width: 18,
                height: 22,
                alignment: Alignment.center,
                child: Icon(
                  Hgi.arrowDown01,
                  size: 11,
                  color: hovering ? AppColors.textPrimary : AppColors.text4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
