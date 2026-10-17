/// A sentence cut into words (incl. punctuation runs) and the text between
/// them: `gaps[0] + words[0] + gaps[1] + … + words[n-1] + gaps[n]`.
class SplitWords {
  const SplitWords(this.words, this.starts, this.gaps);

  final List<String> words;

  /// Offset of each word in the source sentence.
  final List<int> starts;
  final List<String> gaps;

  String join(List<String> replacement) {
    final b = StringBuffer(gaps[0]);
    for (var i = 0; i < replacement.length; i++) {
      b
        ..write(replacement[i])
        ..write(gaps[i + 1]);
    }
    return b.toString();
  }
}

// Dart's \w is ASCII-only, so spell out letters/digits. A word may contain
// RUAccent's "+" stress markers ("к+оса").
final _token = RegExp(
  r'[\p{L}\p{N}_]*(?:\+[\p{L}\p{N}_]+)+|[\p{L}\p{N}_]+|[^\p{L}\p{N}_\s]+',
  unicode: true,
);

SplitWords splitWords(String sentence) {
  final words = <String>[], starts = <int>[], gaps = <String>[];
  var last = 0;
  for (final m in _token.allMatches(sentence)) {
    gaps.add(sentence.substring(last, m.start));
    words.add(m.group(0)!);
    starts.add(m.start);
    last = m.end;
  }
  gaps.add(sentence.substring(last));
  return SplitWords(words, starts, gaps);
}
