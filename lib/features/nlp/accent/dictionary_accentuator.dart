import 'accentuator.dart';
import 'stress_dictionary.dart';

/// Dictionary-only accentuator built on the RUAccent word lists (MIT).
/// Homographs (за́мок / замо́к, все / всё) cannot be resolved without context,
/// so they are left unmarked; see [isAmbiguous].
class DictionaryAccentuator implements Accentuator {
  DictionaryAccentuator({
    required this._stress,
    required this._yoWords,
    required this._omographs,
    required this._yoHomographs,
  });

  final StressDictionary _stress;
  final Map<String, String> _yoWords;
  final Set<String> _omographs;
  final Set<String> _yoHomographs;

  static final _word = RegExp('[А-Яа-яЁё$stressMark]+(?:-[А-Яа-яЁё$stressMark]+)*');

  bool isAmbiguous(String word) {
    final lower = word.toLowerCase();
    return _omographs.contains(lower) || _yoHomographs.contains(lower);
  }

  @override
  Future<String> accent(String text, {bool stress = true, bool yo = true}) async {
    final out = StringBuffer();
    var last = 0;
    for (final m in _word.allMatches(text)) {
      out.write(text.substring(last, m.start));
      out.write(await _accentToken(m.group(0)!, stress, yo));
      last = m.end;
    }
    out.write(text.substring(last));
    return out.toString();
  }

  Future<String> _accentToken(String token, bool stress, bool yo) async {
    if (token.contains(stressMark)) return token;
    if (token.contains('-')) {
      if (stress) {
        final whole = await _stress.stressIndex(token.toLowerCase());
        if (whole != null && !_omographs.contains(token.toLowerCase())) {
          return _insertMark(token, whole);
        }
      }
      final parts = <String>[];
      for (final p in token.split('-')) {
        parts.add(await _accentPart(p, stress, yo));
      }
      return parts.join('-');
    }
    return _accentPart(token, stress, yo);
  }

  Future<String> _accentPart(String part, bool stress, bool yo) async {
    final lower = part.toLowerCase();
    var form = lower;
    var result = part;
    if (yo && !lower.contains('ё') && lower.contains('е') && !_yoHomographs.contains(lower)) {
      final restored = _yoWords[lower];
      if (restored != null && restored.length == lower.length) {
        form = restored;
        result = _applyYo(part, restored);
      }
    }
    if (!stress) return result;
    if (form.contains('ё')) return result; // ё always carries the stress
    if (_vowelCount(form) < 2) return result;
    if (_omographs.contains(form)) return result;
    final idx = await _stress.stressIndex(form);
    if (idx == null || idx >= result.length) return result;
    return _insertMark(result, idx);
  }

  String _applyYo(String original, String restored) {
    final b = StringBuffer();
    for (var i = 0; i < original.length; i++) {
      if (restored[i] == 'ё' && original[i].toLowerCase() == 'е') {
        b.write(original[i] == 'Е' ? 'Ё' : 'ё');
      } else {
        b.write(original[i]);
      }
    }
    return b.toString();
  }

  String _insertMark(String word, int vowelIndex) {
    if (vowelIndex >= word.length || !russianVowels.contains(word[vowelIndex])) {
      return word;
    }
    return '${word.substring(0, vowelIndex + 1)}$stressMark${word.substring(vowelIndex + 1)}';
  }

  int _vowelCount(String w) => w.split('').where(russianVowels.contains).length;
}
