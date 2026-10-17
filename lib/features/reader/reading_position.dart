import 'package:shared_preferences/shared_preferences.dart';

/// Remembers per book which sentence was at the top of the reader, so the
/// book opens where the reader left it, also after the app was closed.
class ReadingPosition {
  const ReadingPosition._();

  static String _key(String bookId) => 'reader.position.$bookId';

  /// Saved sentence index, 0 when none (or when preferences are unavailable).
  static Future<int> load(String bookId) async {
    try {
      return (await SharedPreferences.getInstance()).getInt(_key(bookId)) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> save(String bookId, int index) async {
    try {
      await (await SharedPreferences.getInstance()).setInt(_key(bookId), index);
    } catch (_) {
      // Not worth interrupting reading for.
    }
  }
}

/// The topmost sentence that is at least partly on screen, from the
/// `(index, trailingEdge)` pairs a positioned list reports (trailing edge is
/// the item's bottom as a fraction of the viewport, > 0 when visible).
int topVisibleIndex(Iterable<(int index, double trailingEdge)> positions) {
  var top = -1;
  for (final (index, trailing) in positions) {
    if (trailing > 0 && (top == -1 || index < top)) top = index;
  }
  return top < 0 ? 0 : top;
}
