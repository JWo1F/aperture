import 'package:flutter/material.dart';

import '../../../../theme/app_theme.dart';
import 'popup_state.dart';
import 'suggestion.dart';

class AutocompletePopup extends StatefulWidget {
  const AutocompletePopup({
    super.key,
    required this.state,
    required this.onPick,
    required this.onHover,
    required this.fontSize,
  });

  final PopupState state;
  final ValueChanged<CodeSuggestion> onPick;
  final ValueChanged<int> onHover;
  final double fontSize;

  @override
  State<AutocompletePopup> createState() => _AutocompletePopupState();
}

class _AutocompletePopupState extends State<AutocompletePopup> {
  final ScrollController _scroll = ScrollController();
  // Tall enough to clear descenders (`y`, `g`, `p`) and the `_` underscore
  // in monospace identifiers like `created_at` at fontSize 13. The fixed
  // extent powers cheap scroll-to-selected math; if the popup font ever
  // grows past ~14 this needs to grow with it.
  static const double _rowHeight = 26;

  @override
  void didUpdateWidget(covariant AutocompletePopup old) {
    super.didUpdateWidget(old);
    if (old.state.selected != widget.state.selected ||
        old.state.items.length != widget.state.items.length) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureSelectedVisible(),
      );
    }
  }

  void _ensureSelectedVisible() {
    if (!_scroll.hasClients) return;
    final selected = widget.state.selected;
    final top = selected * _rowHeight;
    final bottom = top + _rowHeight;
    final viewportTop = _scroll.offset;
    final viewportBottom = viewportTop + _scroll.position.viewportDimension;
    if (top < viewportTop) {
      _scroll.jumpTo(top);
    } else if (bottom > viewportBottom) {
      _scroll.jumpTo(bottom - _scroll.position.viewportDimension);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final fontSize = widget.fontSize;
    final onPick = widget.onPick;
    // The popup lives in the root overlay. Without TextFieldTapRegion a
    // pointer-down inside it counts as "outside" to the host TextField,
    // which yields focus → our focus listener dismisses the popup before
    // GestureDetector.onTap ever fires → click silently closes the menu
    // instead of accepting the row.
    return TextFieldTapRegion(
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(
            minWidth: 240,
            maxWidth: 380,
            maxHeight: 260,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: Radii.brSm,
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: Radii.brSm,
            child: ListView.builder(
              controller: _scroll,
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemExtent: _rowHeight,
              itemCount: state.items.length,
              itemBuilder: (context, i) {
                final s = state.items[i];
                final active = i == state.selected;
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => widget.onHover(i),
                  onHover: (_) => widget.onHover(i),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onPick(s),
                    child: Container(
                      color: active
                          ? AppColors.accentSoft
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          KindChip(kind: s.kind),
                          const SizedBox(width: 8),
                          if (s.icon != null) ...[
                            Icon(
                              s.icon,
                              size: 11,
                              color: active
                                  ? AppColors.accent
                                  : AppColors.textMuted,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              s.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppTheme.monoFamily,
                                fontSize: fontSize,
                                color: active
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                                fontWeight: active
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (s.detail != null) ...[
                            const SizedBox(width: 10),
                            Text(
                              s.detail!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.mono(
                                size: fontSize - 1,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 14×14 letter chip on the popup's left edge — gives a quick visual
/// indicator of suggestion kind so a list of mixed columns/tables/
/// keywords stays scannable. Letter+colour are the only signal; the
/// font is tiny so it doesn't compete with the suggestion label.
class KindChip extends StatelessWidget {
  const KindChip({super.key, required this.kind});

  final SuggestionKind kind;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (kind) {
      SuggestionKind.column => ('c', AppColors.accent),
      SuggestionKind.alias => ('a', AppColors.accent),
      SuggestionKind.table => ('t', AppColors.success),
      SuggestionKind.snippet => ('→', AppColors.success),
      SuggestionKind.keyword => ('k', AppColors.textMuted),
    };
    return Container(
      width: 14,
      height: 14,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTheme.monoFamily,
          fontSize: 9.5,
          height: 1,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
