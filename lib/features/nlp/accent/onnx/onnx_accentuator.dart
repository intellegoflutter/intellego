import '../accentuator.dart';
import '../stress_dictionary.dart';
import 'models.dart';
import 'word_splitter.dart';

/// Port of the RUAccent v1 pipeline (MIT, github.com/Den4ikAI/ruaccent):
/// ё restoration → homograph resolution → stress placement.
///
/// Differences from the Python original, on purpose:
/// * the input text is never rewritten (RUAccent strips characters and glues
///   punctuation); only stress marks and ё are added;
/// * ё is never given an extra stress mark and one-syllable words stay
///   unmarked;
/// * homograph lookup is case-insensitive.
class OnnxAccentuator implements Accentuator {
  OnnxAccentuator({
    required this._stress,
    required this._yoWords,
    required this._yoHomographs,
    required this._omographs,
    required this._yoResolver,
    required this._stressUsage,
    required this._omographScorer,
    required this._accentPlacer,
  });

  final StressDictionary _stress;
  final Map<String, String> _yoWords;
  final Map<String, String> _yoHomographs;
  final Map<String, List<String>> _omographs;
  final TokenLabeler _yoResolver;
  final TokenLabeler _stressUsage;
  final OmographScorer _omographScorer;
  final AccentPlacer _accentPlacer;

  static const _vowels = 'аеёиоуыэюяАЕЁИОУЫЭЮЯ';
  static final _hasLetter = RegExp(r'[А-Яа-яЁё]');
  static final _acuteAfterVowel = RegExp('([$_vowels])$stressMark');
  static final _sentenceEnd = RegExp(r'(?<=[.!?…]["»”’)]*)\s+(?=\S)');

  @override
  Future<String> accent(
    String text, {
    bool stress = true,
    bool yo = true,
  }) async {
    if (!stress && !yo) return text;
    // Models see one sentence at a time; keep paragraph breaks intact.
    final out = StringBuffer();
    var last = 0;
    for (final m in _sentenceEnd.allMatches(text)) {
      out
        ..write(await _sentence(text.substring(last, m.start), stress, yo))
        ..write(m.group(0));
      last = m.end;
    }
    out.write(await _sentence(text.substring(last), stress, yo));
    return out.toString();
  }

  Future<String> _sentence(String raw, bool stress, bool yo) async {
    if (!_hasLetter.hasMatch(raw)) return raw;
    // Existing acute marks become RUAccent's "+vowel" so they are kept.
    final sentence = raw.replaceAllMapped(_acuteAfterVowel, (m) => '+${m[1]}');
    final split = splitWords(sentence);
    final words = [...split.words];

    if (yo) await _restoreYo(sentence, split, words);
    if (stress) {
      await _resolveOmographs(words);
      await _placeStress(sentence, split, words);
    }
    return split.join([for (final w in words) _render(w)]);
  }

  Future<void> _restoreYo(
    String sentence,
    SplitWords split,
    List<String> words,
  ) async {
    Map<int, String>? labels;
    if (sentence.toLowerCase().contains('е')) {
      labels = await _yoResolver.labelByStart(sentence.toLowerCase());
    }
    for (var i = 0; i < words.length; i++) {
      final lower = words[i].toLowerCase();
      if (lower.contains('+')) continue;
      var replacement = _yoWords[lower];
      if (labels?[split.starts[i]] == 'YO') {
        replacement = _yoHomographs[lower] ?? replacement;
      }
      if (replacement != null) words[i] = _matchCase(words[i], replacement);
    }
  }

  Future<void> _resolveOmographs(List<String> words) async {
    for (var i = 0; i < words.length; i++) {
      final variants = _omographs[words[i].toLowerCase()];
      if (variants == null || words[i].contains('+')) continue;
      final marked = [
        for (var j = 0; j < words.length; j++)
          j == i ? ' <w>${words[j]}</w> ' : words[j],
      ];
      final choice = await _omographScorer.pick(
        _joinForModel(marked),
        variants,
      );
      words[i] = _matchCase(words[i], variants[choice]);
    }
  }

  Future<void> _placeStress(
    String sentence,
    SplitWords split,
    List<String> words,
  ) async {
    final usage = await _stressUsage.labelByStart(sentence);
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      if (word.contains('+') || !_hasLetter.hasMatch(word)) continue;
      if (_vowelCount(word) < 2 || word.toLowerCase().contains('ё')) continue;
      if ((usage[split.starts[i]] ?? 'STRESS') != 'STRESS') continue;
      final lower = word.toLowerCase();
      final idx = await _stress.stressIndex(lower);
      if (idx != null && idx < word.length) {
        words[i] = '${word.substring(0, idx)}+${word.substring(idx)}';
      } else {
        words[i] = await _accentPlacer.putAccent(word);
      }
    }
  }

  /// RUAccent's `delete_spaces_before_punc` applied to the model input.
  String _joinForModel(List<String> parts) {
    var text = parts.join(' ');
    for (final c in '!"#\$%&\'()*,./:;<=>?@[\\]^_`{|}-'.split('')) {
      if (c == '-') text = text.replaceAll(' $c', c).replaceAll('$c ', c);
      text = text.replaceAll(' $c', c);
    }
    return text;
  }

  /// "+а" → "а" + U+0301; a "+" before ё is dropped (ё is always stressed).
  String _render(String word) {
    if (!word.contains('+')) return word;
    final out = StringBuffer();
    final chars = word.split('');
    for (var i = 0; i < chars.length; i++) {
      if (chars[i] != '+') {
        out.write(chars[i]);
        continue;
      }
      if (i + 1 >= chars.length) continue;
      final next = chars[++i];
      out.write(next);
      if (next != 'ё' && next != 'Ё' && _vowels.contains(next)) {
        out.write(stressMark);
      }
    }
    return out.toString();
  }

  /// Copies upper/lower case of [source] onto [target] ('+' is ignored for
  /// the position mapping).
  String _matchCase(String source, String target) {
    final letters = target.replaceAll('+', '');
    if (letters.length != source.length) return target;
    final b = StringBuffer();
    var s = 0;
    for (final ch in target.split('')) {
      if (ch == '+') {
        b.write(ch);
        continue;
      }
      final src = source[s++];
      b.write(src != src.toLowerCase() ? ch.toUpperCase() : ch);
    }
    return b.toString();
  }

  int _vowelCount(String w) => w.split('').where(_vowels.contains).length;
}
