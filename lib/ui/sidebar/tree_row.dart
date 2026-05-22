import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../widgets/common.dart';

/// Row skeleton shared by every entry in the schema tree (`SchemaBlock`,
/// `TableRow`, `DetailFolder`, `DetailLeaf`, `SavedQueryRow`): horizontal
/// margin, hover tint, indent-based left padding, and the optional left
/// rail + tinted background that mark an active selection. Callers supply
/// only the row's inner [children]; pass [childrenBuilder] instead when
/// those children depend on hover state (e.g. a hover-revealed star
/// button).
class TreeRow extends StatelessWidget {
  const TreeRow({
    super.key,
    required this.indent,
    required this.height,
    this.children,
    this.childrenBuilder,
    this.active = false,
    this.tint,
    this.onTap,
    this.onSecondaryTapDown,
    this.padding,
    this.cursor,
  }) : assert(
         (children == null) != (childrenBuilder == null),
         'Provide exactly one of children or childrenBuilder',
       );

  final int indent;
  final double height;
  final List<Widget>? children;
  final List<Widget> Function(bool hovering)? childrenBuilder;
  final bool active;
  final Color? tint;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final EdgeInsetsGeometry? padding;
  final MouseCursor? cursor;

  @override
  Widget build(BuildContext context) {
    final resolvedPadding =
        padding ?? EdgeInsets.only(left: 14.0 + indent * 18.0, right: 6);
    final row = Hoverable(
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTapDown,
      cursor: cursor ?? SystemMouseCursors.click,
      builder: (context, hovering) {
        final activeTint = tint;
        final rowBg = active && activeTint != null
            ? activeTint.withValues(alpha: 0.13)
            : (hovering ? AppColors.sidebarRowHover : Colors.transparent);
        return Container(
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: resolvedPadding,
          decoration: BoxDecoration(
            color: rowBg,
            borderRadius: Radii.brSm,
          ),
          child: Row(
            children: children ?? childrenBuilder!(hovering),
          ),
        );
      },
    );

    if (!active || tint == null) return row;
    final activeTint = tint!;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        row,
        Positioned(
          left: 0,
          top: 5,
          bottom: 5,
          child: Container(
            width: 2.5,
            decoration: BoxDecoration(
              color: activeTint,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(2),
                bottomRight: Radius.circular(2),
              ),
              boxShadow: [
                BoxShadow(
                  color: activeTint.withValues(alpha: 0.45),
                  blurRadius: 6,
                  spreadRadius: 0,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
