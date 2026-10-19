import '../nlp/accent/accentuator.dart' show stressMark;

/// A word of a sentence and where it sits in the text.
class WordToken {
  const WordToken(this.start, this.end, this.text);

  final int start, end;
  final String text;
}

// Letters, digits and combining marks (the stress mark U+0301 is one), with
// hyphens between parts: "кто-то", "по-русски".
final _word = RegExp(
  r'[\p{L}\p{M}\p{N}_]+(?:[-‑][\p{L}\p{M}\p{N}_]+)*',
  unicode: true,
);

/// The words of [text], in order. Punctuation and spaces are the gaps.
List<WordToken> tokenizeWords(String text) => [
  for (final m in _word.allMatches(text))
    WordToken(m.start, m.end, m.group(0)!),
];

/// The form used to look a word up and to recognise it again: lower case,
/// stress mark removed, ё kept (все and всё are different words).
String lookupForm(String word) => word.toLowerCase().replaceAll(stressMark, '');

/// A word is looked up only when it has a letter.
bool isLookupWord(String token) =>
    RegExp(r'\p{L}', unicode: true).hasMatch(token);
