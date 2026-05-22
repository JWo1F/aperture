import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import 'cell_style.dart';
import 'grid_metrics.dart';

/// One grid cell painted from the shared visual contract: the row-fill blend,
/// the edit accent stripe + soft fill, the right (and optional bottom)
/// hairline, the focus ring, the selection tint, and the deleted-row dimming.
///
/// `GridRow` composes this for the strip of cells inside a row and supplies
/// only the per-cell state; the row paints its own hover / selection / focus
/// overlays once at the row level, so `GridRow` passes `isHovered`,
/// `isRowSelected`, `isSelected` and `isFocus` as `false` and lets the row
/// layer those tints itself.
///
/// `ResultsGrid._buildExpansion` composes this as a standalone floating cell —
/// it sets [backdrop] so the translucent row fill is pre-blended over an
/// opaque colour, sets [bottomBorder] (since there is no row carrying one),
/// and supplies `isHovered`, selection and focus flags directly so the cell
/// paints its own state instead of delegating to a row.
class GridCell extends StatelessWidget {
  const GridCell({
    super.key,
    required this.width,
    required this.content,
    required this.isInsert,
    required this.isDeleted,
    required this.isEdited,
    this.maxWidth,
    this.isHovered = false,
    this.isRowSelected = false,
    this.isSelected = false,
    this.isFocus = false,
    this.backdrop,
    this.bottomBorder = false,
  });

  final double width;
  final double? maxWidth;
  final InlineSpan content;
  final bool isInsert;
  final bool isDeleted;
  final bool isEdited;
  final bool isHovered;
  final bool isRowSelected;
  final bool isSelected;
  final bool isFocus;

  /// Opaque colour the row fill is pre-blended over. When null the cell paints
  /// the row fill (and the edit `accentSoft`) translucently — the row body
  /// underneath supplies the opacity. Set this when the cell is rendered as a
  /// free-floating overlay so the tints don't disappear into whatever sits
  /// behind it.
  final Color? backdrop;

  /// Paints the row's bottom hairline as part of the cell. Used by the hover
  /// expansion since it has no enclosing row to draw that line for it.
  final bool bottomBorder;

  @override
  Widget build(BuildContext context) {
    final Color? fill;
    if (backdrop != null) {
      var blended = Color.alphaBlend(
        gridRowFill(
          isInsert: isInsert,
          isDeleted: isDeleted,
          isHovered: isHovered,
          isRowSelected: isRowSelected,
        ),
        backdrop!,
      );
      if (isEdited) blended = Color.alphaBlend(AppColors.accentSoft, blended);
      fill = blended;
    } else {
      fill = isEdited ? AppColors.accentSoft : null;
    }

    final Widget body = Container(
      width: maxWidth == null ? width : null,
      height: kRowHeight,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      constraints: maxWidth == null
          ? null
          : BoxConstraints(minWidth: width, maxWidth: maxWidth!),
      decoration: BoxDecoration(
        color: fill,
        border: Border(
          right: BorderSide(color: AppColors.hairline, width: 1),
          left: isEdited
              ? BorderSide(color: AppColors.accent, width: 2)
              : BorderSide.none,
          bottom: bottomBorder
              ? BorderSide(color: AppColors.hairline, width: 1)
              : BorderSide.none,
        ),
      ),
      child: maxWidth == null
          ? Text.rich(
              content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          // The Align hugs the text horizontally (widthFactor: 1) so the cell
          // box only grows to the natural glyph run, while still centring it
          // vertically inside the row.
          : Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: Text.rich(
                content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
    );

    Widget cell = body;
    if (isSelected || isFocus) {
      cell = Stack(
        children: [
          cell,
          if (isSelected)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: AppColors.gridRowSelection),
              ),
            ),
          if (isFocus)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.fromBorderSide(
                      BorderSide(color: AppColors.accent, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return isDeleted ? Opacity(opacity: 0.55, child: cell) : cell;
  }
}
