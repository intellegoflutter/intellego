import '../../data/book.dart';

final _headingWord = RegExp(
  r'^(глава|часть|книга|раздел|chapter|part|book)(\s|$)',
  caseSensitive: false,
);

final _standalone = RegExp(
  r'^(пролог|эпилог|предисловие|послесловие|введение|заключение|'
  r'prologue|epilogue)$',
  caseSensitive: false,
);

final _numeral = RegExp(r'^([IVXLCМ]{1,8}|\d{1,3})$');

/// Whether [text] looks like a chapter heading: a short line such as
/// "Глава 3", "Часть вторая", "Эпилог", or just a numeral.
bool looksLikeChapterTitle(String text) {
  final t = text.trim().replaceAll(RegExp(r'[.\s]+$'), '');
  if (t.isEmpty || t.length > 60) return false;
  return _headingWord.hasMatch(t) ||
      _standalone.hasMatch(t) ||
      _numeral.hasMatch(t);
}

/// Chapters found by looking for heading-like paragraphs that consist of a
/// single short sentence.
List<Chapter> detectChapters(List<BookSentence> sentences) {
  final out = <Chapter>[];
  for (var i = 0; i < sentences.length; i++) {
    final p = sentences[i].paragraph;
    final alone =
        (i == 0 || sentences[i - 1].paragraph != p) &&
        (i == sentences.length - 1 || sentences[i + 1].paragraph != p);
    if (alone && looksLikeChapterTitle(sentences[i].text)) {
      out.add(
        Chapter(
          title: sentences[i].text.trim().replaceAll(RegExp(r'[.\s]+$'), ''),
          sentenceIndex: i,
        ),
      );
    }
  }
  return out;
}

/// Chapters for the paragraphs in [headings]: each starts at the first
/// sentence of its paragraph.
List<Chapter> chaptersFromHeadings(
  List<BookSentence> sentences,
  Set<int> headings,
) {
  final out = <Chapter>[];
  final seen = <int>{};
  for (var i = 0; i < sentences.length; i++) {
    final p = sentences[i].paragraph;
    if (headings.contains(p) && seen.add(p)) {
      out.add(Chapter(title: sentences[i].text.trim(), sentenceIndex: i));
    }
  }
  return out;
}

/// [detected] merged into [existing]; a chapter already at the same sentence
/// is kept as it is (it may have been renamed by hand).
List<Chapter> mergeChapters(List<Chapter> existing, List<Chapter> detected) {
  final at = {for (final c in existing) c.sentenceIndex};
  return [
    ...existing,
    for (final c in detected)
      if (!at.contains(c.sentenceIndex)) c,
  ]..sort((a, b) => a.sentenceIndex.compareTo(b.sentenceIndex));
}
