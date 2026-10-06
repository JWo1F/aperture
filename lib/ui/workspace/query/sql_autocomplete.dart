import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../../theme/app_theme.dart';
import '../../widgets/code_editor/suggestions/suggestion.dart';
import '../../widgets/code_editor/token.dart';
import '../../widgets/code_editor/suggestions/popup_widget.dart' show KindChip;

/// Offset of [position] into the editor's text as one string, lines joined
/// by `\n` — the coordinates the SQL tooling speaks.
int flatOffset(CodeLines lines, CodeLinePosition position) {
  var offset = 0;
  for (var i = 0; i < position.index; i++) {
    offset += lines[i].length + 1;
  }
  return offset + position.offset;
}

/// Feeds re_editor's autocomplete from the SQL completion engine.
///
/// re_editor asks on every keystroke of user input and hands over only the
/// caret's line, so the whole text and the flat caret offset are read from
/// [controller]. It opens only on typed input: there is no manual trigger,
/// and nothing reopens the list after a suggestion is accepted.
class SqlPromptsBuilder implements CodeAutocompletePromptsBuilder {
  SqlPromptsBuilder({required this.controller, required this.suggest});

  final CodeLineEditingController controller;

  /// Synchronous: re_editor builds its prompt list inline.
  final List<CodeSuggestion> Function(SuggestRequest) suggest;

  @override
  CodeAutocompleteEditingValue? build(
    BuildContext context,
    CodeLine codeLine,
    CodeLineSelection selection,
  ) {
    final text = controller.text;
    final cursor = flatOffset(controller.codeLines, selection.extent);
    final start = tokenStart(text, cursor);
    final token = text.substring(start, cursor);
    final items = suggest(
      SuggestRequest(
        text: text,
        cursor: cursor,
        token: token,
        tokenStart: start,
      ),
    );
    if (items.isEmpty) return null;
    return CodeAutocompleteEditingValue(
      input: token,
      prompts: [for (final s in items) SqlPrompt(s, input: token)],
      index: 0,
    );
  }
}

class SqlPrompt extends CodePrompt {
  SqlPrompt(this.suggestion, {required this.input})
    : super(word: suggestion.label);

  final CodeSuggestion suggestion;
  final String input;

  /// The caret lands at the end of the word. `selection` is measured from
  /// the word's start; [CodeAutocompleteEditingValue.autocomplete] rebases
  /// it onto the caret's position before the replacement, so a pick must go
  /// through that getter rather than read this one directly.
  @override
  CodeAutocompleteResult get autocomplete => CodeAutocompleteResult(
    input: input,
    word: suggestion.insertText,
    selection: TextSelection.collapsed(offset: suggestion.insertText.length),
  );

  @override
  bool match(String input) => true;
}

/// The suggestion list, drawn like the rest of the app's popups.
class SqlAutocompleteView extends StatefulWidget
    implements PreferredSizeWidget {
  const SqlAutocompleteView({
    super.key,
    required this.notifier,
    required this.onSelected,
  });

  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;

  static const double rowHeight = 26;
  static const double _width = 360;
  static const double _maxHeight = 260;

  @override
  Size get preferredSize {
    final rows = notifier.value.prompts.length;
    final h = rows * rowHeight + 8;
    return Size(_width, h < _maxHeight ? h : _maxHeight);
  }

  @override
  State<SqlAutocompleteView> createState() => _SqlAutocompleteViewState();
}

class _SqlAutocompleteViewState extends State<SqlAutocompleteView> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onChange);
    _scroll.dispose();
    super.dispose();
  }

  void _onChange() {
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _keepSelectedVisible());
  }

  void _keepSelectedVisible() {
    if (!mounted || !_scroll.hasClients) return;
    final top = widget.notifier.value.index * SqlAutocompleteView.rowHeight;
    final bottom = top + SqlAutocompleteView.rowHeight;
    final view = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (bottom > _scroll.offset + view) {
      _scroll.jumpTo(bottom - view);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.notifier.value;
    return Container(
      width: widget.preferredSize.width,
      height: widget.preferredSize.height,
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
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemExtent: SqlAutocompleteView.rowHeight,
          itemCount: value.prompts.length,
          itemBuilder: (context, i) => _row(value.prompts[i] as SqlPrompt, i),
        ),
      ),
    );
  }

  Widget _row(SqlPrompt prompt, int i) {
    final s = prompt.suggestion;
    final active = i == widget.notifier.value.index;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) =>
          widget.notifier.value = widget.notifier.value.copyWith(index: i),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSelected(
          widget.notifier.value.copyWith(index: i).autocomplete,
        ),
        child: Container(
          color: active
              ? AppColors.accentSoft
              : AppColors.accentSoft.withValues(alpha: 0),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              KindChip(kind: s.kind),
              const SizedBox(width: 8),
              if (s.icon != null) ...[
                Icon(
                  s.icon,
                  size: 11,
                  color: active ? AppColors.accent : AppColors.textMuted,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  s.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono(
                    size: 12,
                    color: active
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              if (s.detail != null) ...[
                const SizedBox(width: 10),
                Text(
                  s.detail!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono(size: 11, color: AppColors.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
