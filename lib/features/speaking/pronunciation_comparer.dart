/// Compares what a speech recogniser heard with the sentence the user was
/// meant to read, word by word.
///
/// A transcript can tell that a word was skipped, replaced or garbled, but not
/// that its stress was wrong while the word itself was recognised. Stress is
/// therefore shown from the accented sentence for every word that went wrong,
/// not detected.
library;

const stressMark = '́';

enum WordStatus {
  /// Heard as expected.
  correct,

  /// Replaced by a different word ([WordResult.heard]); [WordResult.similarity]
  /// tells a near miss from a different word.
  misheard,

  /// Expected but not heard.
  missed,

  /// Heard but not in the sentence.
  extra,
}

class WordResult {
  const WordResult(
    this.status, {
    this.expected,
    this.heard,
    this.similarity = 0,
  });

  final WordStatus status;

  /// The word as printed in the accented sentence (with stress marks), null
  /// for [WordStatus.extra].
  final String? expected;

  /// The word as recognised, null for [WordStatus.missed].
  final String? heard;

  /// 0..1 closeness of [heard] to [expected] (letters only).
  final double similarity;

  /// A substitution that is close to the expected word.
  bool get nearMiss => status == WordStatus.misheard && similarity >= 0.6;

  @override
  String toString() => 'WordResult($status, $expected, $heard)';
}

class Comparison {
  const Comparison(this.words);

  final List<WordResult> words;

  Iterable<WordResult> get _expected =>
      words.where((w) => w.status != WordStatus.extra);

  int get expectedCount => _expected.length;
  int get correctCount =>
      words.where((w) => w.status == WordStatus.correct).length;

  /// Share of the expected words that were heard correctly, 0..1.
  double get score => expectedCount == 0 ? 0 : correctCount / expectedCount;

  bool get perfect => words.every((w) => w.status == WordStatus.correct);

  /// Words to work on: everything but the correct ones, in sentence order.
  List<WordResult> get problems =>
      words.where((w) => w.status != WordStatus.correct).toList();
}

/// Lower-case letters only, ё folded to е, stress marks and punctuation gone.
/// Empty when the token holds no letters (dashes, quotes).
String normalizeWord(String word) {
  final b = StringBuffer();
  for (final r in word.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    if (c == stressMark) continue;
    if (c == 'ё') {
      b.write('е');
    } else if (RegExp(r'[a-zа-я]').hasMatch(c)) {
      b.write(c);
    }
  }
  return b.toString();
}

/// Splits [text] into comparable words: `(display form, normalised key)`.
/// Hyphenated words become several, because recognisers write them apart.
/// Tokens with digits are dropped: they are spoken as words the text does not
/// contain.
List<(String shown, String key)> comparableWords(String text) {
  final out = <(String, String)>[];
  for (final token in text.split(RegExp(r'\s+'))) {
    if (token.isEmpty || RegExp(r'\d').hasMatch(token)) continue;
    for (final part in token.split(RegExp(r'[-‐‑–—]'))) {
      final key = normalizeWord(part);
      if (key.isNotEmpty) {
        out.add((
          part.replaceAll(RegExp(r'^[^\wа-яёА-ЯЁ]+|[^\wа-яёА-ЯЁ́]+$'), ''),
          key,
        ));
      }
    }
  }
  return out;
}

double _similarity(String a, String b) {
  if (a == b) return 1;
  final longest = a.length > b.length ? a.length : b.length;
  if (longest == 0) return 1;
  return 1 - _levenshtein(a, b) / longest;
}

int _levenshtein(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final sub =
          prev[j - 1] + (a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1);
      cur[j] = [
        sub,
        prev[j] + 1,
        cur[j - 1] + 1,
      ].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// Aligns the [heard] transcript to [accented] (the sentence with stress
/// marks; stress-free text works too).
Comparison compareWords({required String accented, required String heard}) {
  final exp = comparableWords(accented);
  final got = comparableWords(heard);
  final n = exp.length, m = got.length;

  // cost[i][j]: cheapest alignment of the first i expected / j heard words.
  final cost = List.generate(n + 1, (_) => List<double>.filled(m + 1, 0));
  for (var i = 1; i <= n; i++) {
    cost[i][0] = i.toDouble();
  }
  for (var j = 1; j <= m; j++) {
    cost[0][j] = j.toDouble();
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final s = 1 - _similarity(exp[i - 1].$2, got[j - 1].$2);
      cost[i][j] = [
        cost[i - 1][j - 1] + s,
        cost[i - 1][j] + 1,
        cost[i][j - 1] + 1,
      ].reduce((x, y) => x < y ? x : y);
    }
  }

  final out = <WordResult>[];
  var i = n, j = m;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0) {
      final sim = _similarity(exp[i - 1].$2, got[j - 1].$2);
      if ((cost[i][j] - (cost[i - 1][j - 1] + 1 - sim)).abs() < 1e-9) {
        out.add(
          sim == 1
              ? WordResult(
                  WordStatus.correct,
                  expected: exp[i - 1].$1,
                  heard: got[j - 1].$1,
                  similarity: 1,
                )
              : WordResult(
                  WordStatus.misheard,
                  expected: exp[i - 1].$1,
                  heard: got[j - 1].$1,
                  similarity: sim,
                ),
        );
        i--;
        j--;
        continue;
      }
    }
    if (i > 0 && (j == 0 || (cost[i][j] - (cost[i - 1][j] + 1)).abs() < 1e-9)) {
      out.add(WordResult(WordStatus.missed, expected: exp[i - 1].$1));
      i--;
    } else {
      out.add(WordResult(WordStatus.extra, heard: got[j - 1].$1));
      j--;
    }
  }
  return Comparison(out.reversed.toList());
}

const _vowels = 'аеёиоуыэюяАЕЁИОУЫЭЮЯ';

/// 1-based syllable of [word] that carries the stress mark, or null when it
/// has none. A word with `ё` is stressed on it.
int? stressedSyllable(String word) {
  var syllable = 0;
  final runes = word.runes.toList();
  for (var k = 0; k < runes.length; k++) {
    final c = String.fromCharCode(runes[k]);
    if (!_vowels.contains(c)) continue;
    syllable++;
    final next = k + 1 < runes.length ? String.fromCharCode(runes[k + 1]) : '';
    if (next == stressMark || c == 'ё' || c == 'Ё') return syllable;
  }
  return null;
}

int syllableCount(String word) =>
    word.runes.where((r) => _vowels.contains(String.fromCharCode(r))).length;
