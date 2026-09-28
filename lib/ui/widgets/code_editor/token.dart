/// First word-character offset preceding [cursor], inclusive. A word char
/// is `[A-Za-z0-9_]`. With no word chars behind the caret returns [cursor].
int tokenStart(String text, int cursor) {
  var i = cursor;
  while (i > 0 && _isWord(text.codeUnitAt(i - 1))) {
    i--;
  }
  return i;
}

bool _isWord(int c) =>
    (c >= 0x30 && c <= 0x39) || // 0-9
    (c >= 0x41 && c <= 0x5A) || // A-Z
    (c >= 0x61 && c <= 0x7A) || // a-z
    c == 0x5F; // _
