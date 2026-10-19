import '../../data/book.dart';
import '../nlp/accent/accentuator.dart' show stressMark;

/// Lower case, stress marks removed and ё written as е, so that a query
/// matches regardless of how the text is accented.
String normalizeForSearch(String s) =>
    s.toLowerCase().replaceAll(stressMark, '').replaceAll('ё', 'е');

class SearchHit {
  const SearchHit({
    required this.index,
    required this.field,
    required this.text,
    required this.start,
    required this.end,
  });

  /// Sentence index.
  final int index;

  /// Where it was found: null for the Russian text, otherwise the name of the
  /// translation.
  final String? field;

  /// The text that matched (the accented Russian text or the translation).
  final String text;

  /// The matched range inside [text].
  final int start;
  final int end;
}

/// Maps each character of [accented] to its position in the normalized text,
/// so that a match found in the normalized form can be shown on the original.
({String normalized, List<int> origin}) _normalizeWithMap(String accented) {
  final buf = StringBuffer();
  final origin = <int>[];
  for (var i = 0; i < accented.length; i++) {
    final c = accented[i];
    if (c == stressMark) continue;
    final n = c.toLowerCase().replaceAll('ё', 'е');
    for (var k = 0; k < n.length; k++) {
      buf.write(n[k]);
      origin.add(i);
    }
  }
  return (normalized: buf.toString(), origin: origin);
}

/// Sentences of [book] that contain [query], in book order. At most one hit
/// per sentence and field; at most [limit] in total.
List<SearchHit> searchBook(
  Book book,
  String query, {
  bool inTranslations = true,
  int limit = 500,
}) {
  final q = normalizeForSearch(query).trim();
  if (q.length < 2) return const [];
  final hits = <SearchHit>[];
  for (var i = 0; i < book.sentences.length && hits.length < limit; i++) {
    final text = book.sentences[i].accented;
    final m = _normalizeWithMap(text);
    final at = m.normalized.indexOf(q);
    if (at >= 0) {
      hits.add(
        SearchHit(
          index: i,
          field: null,
          text: text,
          start: m.origin[at],
          end: m.origin[at + q.length - 1] + 1,
        ),
      );
    }
    if (!inTranslations) continue;
    for (final t in book.translations) {
      if (i >= t.lines.length) continue;
      final line = t.lines[i];
      final lineAt = normalizeForSearch(line).indexOf(q);
      if (lineAt >= 0) {
        hits.add(
          SearchHit(
            index: i,
            field: t.name,
            text: line,
            start: lineAt,
            end: lineAt + q.length,
          ),
        );
      }
    }
  }
  return hits;
}

/// Chapters whose title contains [query].
List<Chapter> searchChapters(Book book, String query) {
  final q = normalizeForSearch(query).trim();
  if (q.isEmpty) return const [];
  return [
    for (final c in book.chapters)
      if (normalizeForSearch(c.title).contains(q)) c,
  ];
}
