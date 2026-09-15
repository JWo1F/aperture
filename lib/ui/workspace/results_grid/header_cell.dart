import 'package:flutter/material.dart';

import '../../../models/db_object.dart';
import '../../../models/order_term.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import '../../widgets/common.dart';
import 'grid_metrics.dart';

/// A results-grid header cell: a sortable label area (with PK / FK glyph and
/// sort indicator) plus a trailing drag handle for column resize.
class HeaderCell extends StatelessWidget {
  const HeaderCell({
    super.key,
    required this.label,
    required this.width,
    required this.onResize,
    required this.sort,
    required this.sortPriority,
    this.onSort,
    this.meta,
    this.foreignKey,
  });

  final String label;
  final double width;
  final ValueChanged<double> onResize;
  final OrderTerm? sort;
  final int sortPriority;
  final VoidCallback? onSort;
  final DbColumn? meta;
  final DbForeignKey? foreignKey;

  bool get _isPrimaryKey => meta?.isPrimaryKey ?? false;

  bool get _isForeignKey => foreignKey != null;

  @override
  Widget build(BuildContext context) {
    final sortable = onSort != null;
    final Color nameColor = _isPrimaryKey
        ? AppColors.accent
        : _isForeignKey
        ? AppColors.tFk
        : AppColors.textPrimary;

    Widget hoverable = Hoverable(
      cursor: sortable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onTap: onSort,
      builder: (context, hovering) => Container(
        decoration: BoxDecoration(
          color: hovering && sortable
              ? AppColors.surfaceHover
              : AppColors.bgDeep,
          border: Border(
            right: BorderSide(color: AppColors.hairline, width: 1),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            if (_isPrimaryKey) ...[
              Icon(Hgi.key01, size: 10, color: AppColors.accent),
              const SizedBox(width: 5),
            ] else if (_isForeignKey) ...[
              Icon(Hgi.arrowUpRight01, size: 10, color: AppColors.tFk),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.mono(
                  size: 11,
                  color: nameColor,
                  weight: FontWeight.w600,
                ),
              ),
            ),
            if (sort != null) ...[
              const Spacer(),
              Icon(
                sort!.descending ? Hgi.arrowDown01 : Hgi.arrowUp01,
                size: 11,
                color: AppColors.accent,
              ),
              if (sortPriority > 0) ...[
                const SizedBox(width: 2),
                Text(
                  '$sortPriority',
                  style: AppTheme.mono(
                    size: 9,
                    color: AppColors.accent,
                    weight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );

    final tooltip = _buildTooltip();
    if (tooltip != null) {
      hoverable = Tooltip(
        richMessage: tooltip,
        waitDuration: const Duration(milliseconds: 350),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: Radii.brSm,
          border: Border.all(color: AppColors.border),
        ),
        child: hoverable,
      );
    }

    return SizedBox(
      width: width,
      height: 28,
      child: Stack(
        children: [
          hoverable,
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: kResizeHandleWidth,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (d) => onResize(d.delta.dx),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InlineSpan? _buildTooltip() {
    final meta = this.meta;
    final fk = foreignKey;
    if (meta == null && fk == null) return null;

    final mono = AppTheme.mono(size: 11.5, color: AppColors.textPrimary);
    final monoMuted = AppTheme.mono(size: 11.5, color: AppColors.textMuted);
    final monoAccent = AppTheme.mono(
      size: 11.5,
      color: AppColors.accent,
      weight: FontWeight.w600,
    );
    final monoFk = AppTheme.mono(size: 11.5, color: AppColors.tFk);
    final uiComment = AppTheme.ui(
      size: 11.5,
      color: AppColors.textSecondary,
    ).copyWith(fontStyle: FontStyle.italic);

    final lines = <InlineSpan>[
      TextSpan(
        text: label,
        style: mono.copyWith(fontWeight: FontWeight.w600),
      ),
    ];

    if (meta != null) {
      final mods = <String>[];
      if (!meta.nullable) mods.add('NOT NULL');
      if (meta.hasDefault) mods.add('DEFAULT');
      final detail = mods.isEmpty
          ? meta.dataType
          : '${meta.dataType} · ${mods.join(' · ')}';
      lines.add(TextSpan(text: '\n$detail', style: monoMuted));
    }

    if (meta?.isPrimaryKey ?? false) {
      lines.add(TextSpan(text: '\nPRIMARY KEY', style: monoAccent));
    }

    if (fk != null) {
      final ref = fk.isSingleColumn
          ? '${fk.refSchema}.${fk.refTable}.${fk.refColumns.first}'
          : '${fk.refSchema}.${fk.refTable} (${fk.refColumns.join(", ")})';
      final actions = <String>[];
      if (fk.onUpdate != null && fk.onUpdate!.isNotEmpty) {
        actions.add('ON UPDATE ${fk.onUpdate}');
      }
      if (fk.onDelete != null && fk.onDelete!.isNotEmpty) {
        actions.add('ON DELETE ${fk.onDelete}');
      }
      lines.add(TextSpan(text: '\n→ $ref', style: monoFk));
      if (actions.isNotEmpty) {
        lines.add(TextSpan(text: '\n${actions.join(' · ')}', style: monoMuted));
      }
    }

    final comment = meta?.comment;
    if (comment != null && comment.isNotEmpty) {
      lines.add(TextSpan(text: '\n$comment', style: uiComment));
    }

    return TextSpan(children: lines);
  }
}
