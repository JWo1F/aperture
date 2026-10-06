import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:re_editor/re_editor.dart';

import '../../../theme/app_theme.dart';
import '../../widgets/code_editor/suggestions/suggestion.dart';
import '../../widgets/code_view.dart';
import 'sql_autocomplete.dart';

/// A tappable glyph in the gutter beside one line.
class GutterAction {
  const GutterAction({required this.icon, this.onTap, this.tooltip});

  final Widget icon;
  final VoidCallback? onTap;
  final String? tooltip;
}

/// A wash across lines [startLine]..[endLine] (inclusive, 0-based) with a
/// solid [spine] down its left edge, flush against the gutter.
class LineBand {
  const LineBand({
    required this.startLine,
    required this.endLine,
    required this.color,
    required this.spine,
  });

  final int startLine;
  final int endLine;
  final Color color;
  final Color spine;
}

/// The query page's SQL editor, on `re_editor`: it lays out and paints only
/// the lines in view, so a long script types as fast as a short one.
///
/// The gutter and the statement bands are drawn from the positions of the
/// visible lines that re_editor publishes to its indicator, which is why
/// the editor's own background is transparent — the bands sit beneath the
/// text.
class SqlEditor extends StatefulWidget {
  const SqlEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.bands,
    required this.gutterActions,
    required this.suggest,
  });

  final CodeLineEditingController controller;
  final FocusNode focusNode;
  final List<LineBand> bands;

  /// Keyed by 0-based line.
  final Map<int, GutterAction> gutterActions;
  final List<CodeSuggestion> Function(SuggestRequest) suggest;

  static const double _fontSize = 12.5;
  static const double _lineHeight = 1.45;
  static const double _iconsWidth = 18;

  @override
  State<SqlEditor> createState() => _SqlEditorState();
}

class _SqlEditorState extends State<SqlEditor> {
  /// re_editor hands the visible lines only to the indicator builder; kept
  /// here so the band painter beneath the text can read them too.
  final ValueNotifier<CodeIndicatorValue?> _lines = ValueNotifier(null);

  /// The gutter sizes itself to the line-number digits; its width, read
  /// back from layout, is where the bands start.
  final ValueNotifier<double> _gutterWidth = ValueNotifier(0);
  CodeIndicatorValueNotifier? _source;
  late SqlPromptsBuilder _prompts;

  @override
  void initState() {
    super.initState();
    _prompts = SqlPromptsBuilder(
      controller: widget.controller,
      suggest: (req) => widget.suggest(req),
    );
  }

  @override
  void didUpdateWidget(SqlEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      _prompts = SqlPromptsBuilder(
        controller: widget.controller,
        suggest: (req) => widget.suggest(req),
      );
    }
  }

  @override
  void dispose() {
    _source?.removeListener(_mirror);
    _lines.dispose();
    _gutterWidth.dispose();
    super.dispose();
  }

  void _track(CodeIndicatorValueNotifier source) {
    if (identical(source, _source)) return;
    _source?.removeListener(_mirror);
    _source = source..addListener(_mirror);
    WidgetsBinding.instance.addPostFrameCallback((_) => _mirror());
  }

  // re_editor publishes the visible lines from its layout pass, so this
  // runs mid-layout: whatever listens may repaint, never rebuild.
  void _mirror() {
    if (mounted) _lines.value = _source?.value;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bg,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _BandPainter(
                  lines: _lines,
                  gutterWidth: _gutterWidth,
                  bands: widget.bands,
                ),
              ),
            ),
          ),
          CodeAutocomplete(
            viewBuilder: (context, notifier, onSelected) =>
                SqlAutocompleteView(notifier: notifier, onSelected: onSelected),
            promptsBuilder: _prompts,
            child: _TabAccepts(
              child: CodeEditor(
                controller: widget.controller,
                focusNode: widget.focusNode,
                wordWrap: true,
                padding: const EdgeInsets.fromLTRB(
                  Insets.md,
                  12,
                  Insets.md,
                  12,
                ),
                shortcutsActivatorsBuilder: const AppCodeShortcuts(),
                scrollbarBuilder: codeScrollbar,
                verticalScrollbarWidth: 10,
                chunkAnalyzer: const NonCodeChunkAnalyzer(),
                style: codeEditorStyle(
                  language: CodeLanguage.sql,
                  background: AppColors.bg.withValues(alpha: 0),
                ),
                leadingDivider: Container(width: 1, color: AppColors.hairline),
                indicatorBuilder: (context, editing, chunks, notifier) {
                  _track(notifier);
                  return _SizeReport(
                    width: _gutterWidth,
                    child: ColoredBox(
                      color: AppColors.bg,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 8, right: 6),
                            child: DefaultCodeLineNumber(
                              controller: editing,
                              notifier: notifier,
                              textStyle: AppTheme.mono(
                                size: SqlEditor._fontSize,
                                color: AppColors.text4,
                              ).copyWith(height: SqlEditor._lineHeight),
                              focusedTextStyle: AppTheme.mono(
                                size: SqlEditor._fontSize,
                                color: AppColors.textMuted,
                              ).copyWith(height: SqlEditor._lineHeight),
                            ),
                          ),
                          SizedBox(
                            width: SqlEditor._iconsWidth,
                            child: _GutterIcons(
                              notifier: notifier,
                              actions: widget.gutterActions,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tab accepts the highlighted prompt and Enter always breaks the line.
/// re_editor's own autocomplete takes Enter, by answering the newline
/// intent while its popup is open.
///
/// Before running its handler for a key, the editor asks the nearest
/// ancestor `Actions` for that intent, and invokes it instead when it is
/// enabled. Sitting between the autocomplete and the editor, this hides the
/// autocomplete's newline action behind a disabled one, and enables Tab
/// exactly while that action is — so Tab still indents with no popup open.
class _TabAccepts extends StatelessWidget {
  const _TabAccepts({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      CodeShortcutNewLineIntent: _Disabled<CodeShortcutNewLineIntent>(),
      CodeShortcutIndentIntent: _AcceptPrompt(
        Actions.find<CodeShortcutNewLineIntent>(context),
      ),
    },
    child: child,
  );
}

class _Disabled<T extends Intent> extends Action<T> {
  @override
  bool get isActionEnabled => false;

  @override
  Object? invoke(T intent) => null;
}

// A CallbackAction because the editor invokes no other kind.
class _AcceptPrompt extends CallbackAction<CodeShortcutIndentIntent> {
  _AcceptPrompt(this._accept)
    : super(onInvoke: (_) => _accept.invoke(const CodeShortcutNewLineIntent()));

  final Action<CodeShortcutNewLineIntent> _accept;

  @override
  bool get isActionEnabled => _accept.isActionEnabled;
}

/// One icon per entry of [actions], placed at paint time on its line's
/// current position — the positions change mid-layout, where a rebuild is
/// not allowed. An icon whose line is out of view is not painted, and so
/// not hit-tested either.
class _GutterIcons extends StatelessWidget {
  const _GutterIcons({required this.notifier, required this.actions});

  final CodeIndicatorValueNotifier notifier;
  final Map<int, GutterAction> actions;

  @override
  Widget build(BuildContext context) {
    final entries = actions.entries.toList();
    return ClipRect(
      child: Flow(
        delegate: _GutterFlow(
          notifier: notifier,
          lines: [for (final e in entries) e.key],
        ),
        children: [for (final e in entries) _icon(e.value)],
      ),
    );
  }

  Widget _icon(GutterAction action) {
    return MouseRegion(
      cursor: action.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: action.onTap,
        child: Tooltip(
          message: action.tooltip ?? '',
          waitDuration: const Duration(milliseconds: 400),
          child: Center(child: action.icon),
        ),
      ),
    );
  }
}

class _GutterFlow extends FlowDelegate {
  _GutterFlow({required this.notifier, required this.lines})
    : super(repaint: notifier);

  final CodeIndicatorValueNotifier notifier;
  final List<int> lines;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      BoxConstraints.tightFor(
        width: constraints.maxWidth,
        height: SqlEditor._fontSize * SqlEditor._lineHeight,
      );

  @override
  void paintChildren(FlowPaintingContext context) {
    final visible = notifier.value?.paragraphs;
    if (visible == null) return;
    final tops = {for (final p in visible) p.index: p.top};
    for (var i = 0; i < lines.length; i++) {
      final top = tops[lines[i]];
      if (top == null) continue;
      context.paintChild(i, transform: Matrix4.translationValues(0, top, 0));
    }
  }

  @override
  bool shouldRepaint(_GutterFlow old) =>
      old.notifier != notifier || !_sameLines(old.lines, lines);

  @override
  bool shouldRelayout(_GutterFlow old) => old.lines.length != lines.length;

  static bool _sameLines(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Writes its child's laid-out width to [width].
class _SizeReport extends SingleChildRenderObjectWidget {
  const _SizeReport({required this.width, super.child});

  final ValueNotifier<double> width;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReport(width);

  @override
  void updateRenderObject(BuildContext context, _RenderSizeReport render) {
    render.width = width;
  }
}

class _RenderSizeReport extends RenderProxyBox {
  _RenderSizeReport(this.width);

  ValueNotifier<double> width;

  @override
  void performLayout() {
    super.performLayout();
    width.value = size.width;
  }
}

class _BandPainter extends CustomPainter {
  _BandPainter({
    required this.lines,
    required this.gutterWidth,
    required this.bands,
  }) : super(repaint: Listenable.merge([lines, gutterWidth]));

  final ValueNotifier<CodeIndicatorValue?> lines;
  final ValueNotifier<double> gutterWidth;
  final List<LineBand> bands;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = lines.value?.paragraphs;
    if (visible == null || visible.isEmpty) return;
    // Past the gutter and the 1px divider beside it.
    final left = gutterWidth.value + 1;
    canvas.clipRect(Offset.zero & size);
    for (final band in bands) {
      double? top;
      double? bottom;
      for (final line in visible) {
        if (line.index < band.startLine || line.index > band.endLine) continue;
        top ??= line.top;
        bottom = line.bottom;
      }
      if (top == null || bottom == null) continue;
      final rect = Rect.fromLTRB(left, top, size.width, bottom);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [band.color, band.color.withValues(alpha: 0)],
            stops: const [0.0, 0.8],
          ).createShader(rect),
      );
      canvas.drawRect(
        Rect.fromLTWH(left, top, 2, bottom - top),
        Paint()..color = band.spine,
      );
    }
  }

  @override
  bool shouldRepaint(_BandPainter old) => old.bands != bands;
}
