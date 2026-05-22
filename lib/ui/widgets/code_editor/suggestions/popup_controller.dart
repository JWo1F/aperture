import 'dart:async';

import 'package:flutter/widgets.dart';

import 'popup_state.dart';
import 'suggestion.dart';

/// Owns the autocomplete state machine: debounced suggestion requests,
/// in-flight sequence ordering, a one-shot suppression flag, and the
/// observable [PopupState]. The view layer listens to [popup] and renders
/// the popup; it forwards key/focus/text events into this controller.
///
/// Three invariants the old version got wrong:
///   1. Only re-query on actual text edits, not on caret-only moves.
///   2. After accepting a suggestion, swallow exactly one auto-trigger so
///      the controller-change fired by the write doesn't immediately
///      re-open the popup on the freshly inserted word as the new prefix.
///   3. Never open on an empty token unless the user pressed Ctrl-Space.
class PopupController {
  PopupController({
    required this.editingController,
    required this.isFocused,
    required this.isMounted,
    required this.caretAnchor,
    required this.tokenStartOf,
    this.suggest,
  }) : _lastSeenText = editingController.text;

  final TextEditingController editingController;
  final bool Function() isFocused;
  final bool Function() isMounted;
  final Offset Function(int cursor) caretAnchor;
  final int Function(String text, int cursor) tokenStartOf;
  CodeSuggestProvider? suggest;

  /// Tight debounce — enough to coalesce a flurry of edits inside a
  /// single frame, short enough that the popup feels live as you type.
  static const Duration _suggestDelay = Duration(milliseconds: 60);

  final ValueNotifier<PopupState> popup = ValueNotifier(
    const PopupState.hidden(),
  );

  int _suggestSeq = 0;
  Timer? _suggestDebounce;
  String _lastSeenText;
  bool _suppressNextAutoTrigger = false;

  bool get isOpen => !popup.value.isHidden && popup.value.items.isNotEmpty;

  /// Called by the view when the [TextEditingController] notifies a change.
  /// Returns nothing — the view still needs to call setState for non-popup
  /// reasons (e.g. line-number repaint).
  void onEditingChanged() {
    final text = editingController.text;
    final textChanged = text != _lastSeenText;
    _lastSeenText = text;

    if (suggest == null) return;

    if (_suppressNextAutoTrigger) {
      // The accept-suggestion path wrote the controller value, which
      // re-entered this listener. Swallow exactly one trigger so we
      // don't immediately re-open the popup on the inserted word.
      _suppressNextAutoTrigger = false;
    } else if (textChanged) {
      _scheduleSuggest();
    } else if (isOpen) {
      // Selection-only change while the popup is up — if the caret has
      // walked off the active token, hide; otherwise leave it alone.
      _reconcileToCaret();
    }
  }

  /// Tells the controller a non-popup write is about to happen (indent,
  /// newline-insert, etc.) so the resulting controller change doesn't
  /// reopen the popup on whatever text the write produced.
  void suppressNextAutoTrigger() {
    _suppressNextAutoTrigger = true;
  }

  void _scheduleSuggest() {
    _suggestDebounce?.cancel();
    _suggestDebounce = Timer(_suggestDelay, requestSuggestions);
  }

  Future<void> requestSuggestions({bool manualTrigger = false}) async {
    if (!isMounted() || !isFocused()) return;
    final provider = suggest;
    if (provider == null) return;

    final text = editingController.text;
    final cursor = editingController.selection.baseOffset;
    if (cursor < 0 || editingController.selection.extentOffset != cursor) {
      dismiss();
      return;
    }

    final tStart = tokenStartOf(text, cursor);
    final token = text.substring(tStart, cursor);

    // Empty tokens are handed to the provider too — the SQL engine
    // decides whether the cursor sits in a "natural" completion slot
    // (right after `JOIN `, `,`, `(`, …) and returns a non-empty pool
    // there, or returns [] elsewhere so the popup stays hidden.
    final seq = ++_suggestSeq;
    final res = await provider(
      SuggestRequest(
        text: text,
        cursor: cursor,
        token: token,
        tokenStart: tStart,
        manualTrigger: manualTrigger,
      ),
    );
    if (!isMounted() || seq != _suggestSeq) return;

    if (res.isEmpty) {
      dismiss();
      return;
    }

    _show(res, tStart, cursor);
  }

  void _reconcileToCaret() {
    final state = popup.value;
    if (state.isHidden) return;
    final cursor = editingController.selection.baseOffset;
    if (cursor < state.tokenStart || cursor > state.tokenStart + 200) {
      dismiss();
      return;
    }
    final text = editingController.text;
    final liveTokenStart = tokenStartOf(text, cursor);
    if (liveTokenStart != state.tokenStart) {
      dismiss();
    }
  }

  void _show(List<CodeSuggestion> items, int tokenStart, int cursor) {
    popup.value = PopupState(
      items: items,
      selected: 0,
      tokenStart: tokenStart,
      cursor: cursor,
      anchor: caretAnchor(cursor),
    );
  }

  /// Hides the popup. When [suppressNext] is true, also swallow the next
  /// auto-trigger — used by Escape so a debounced suggest in flight
  /// doesn't immediately re-open the popup the user just dismissed.
  void dismiss({bool suppressNext = false}) {
    _suggestSeq++;
    _suggestDebounce?.cancel();
    if (!popup.value.isHidden) popup.value = const PopupState.hidden();
    if (suppressNext) _suppressNextAutoTrigger = true;
  }

  void refreshAnchor() {
    final cur = popup.value;
    if (cur.isHidden) return;
    popup.value = cur.copyWith(anchor: caretAnchor(cur.cursor));
  }

  void move(int delta) {
    final cur = popup.value;
    if (cur.isHidden || cur.items.isEmpty) return;
    final raw = (cur.selected + delta) % cur.items.length;
    popup.value = cur.copyWith(
      selected: raw < 0 ? raw + cur.items.length : raw,
    );
  }

  void setSelected(int index) {
    final cur = popup.value;
    if (cur.isHidden) return;
    if (index < 0 || index >= cur.items.length) return;
    if (cur.selected == index) return;
    popup.value = cur.copyWith(selected: index);
  }

  void accept(CodeSuggestion s) {
    final state = popup.value;
    if (state.isHidden) return;
    final t = editingController.text;
    final before = t.substring(0, state.tokenStart);
    // Replace through to the *current* caret, not the cursor snapshot
    // captured when the popup opened — the user may have typed extra
    // characters between popup-show and accept.
    final liveCursor = editingController.selection.baseOffset.clamp(
      state.tokenStart,
      t.length,
    );
    final after = t.substring(liveCursor);

    // Chained suggestions (keywords, tables, `*`) append a trailing
    // space and re-open the popup for the next slot. Skip the space if
    // the next char is already whitespace so chaining over an existing
    // gap doesn't double up.
    final wantsSpace =
        s.chainNext && (after.isEmpty || !_isSpace(after.codeUnitAt(0)));
    final insert = wantsSpace ? '${s.insertText} ' : s.insertText;

    final newText = '$before$insert$after';
    final caret = state.tokenStart + insert.length;
    _suppressNextAutoTrigger = true;
    editingController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: caret),
    );
    dismiss();

    if (s.chainNext) {
      // Re-open after the controller change has fully propagated.
      // `manualTrigger: true` makes the engine treat an empty token as
      // "show me what fits here" instead of bailing out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isMounted() || !isFocused()) return;
        requestSuggestions(manualTrigger: true);
      });
    }
  }

  void dispose() {
    _suggestDebounce?.cancel();
    popup.dispose();
  }

  static bool _isSpace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
}
