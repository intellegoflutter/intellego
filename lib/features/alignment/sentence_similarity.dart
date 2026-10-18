/// Cheap Russian ↔ Ukrainian sentence similarity based on word stems.
///
/// Both languages are folded onto a common alphabet (і/ї/ы → и, є/э/ё → е,
/// ґ → г, apostrophes dropped) and every word of at least [minWord] letters
/// is reduced to its first [stemLength] letters. Cognates and names then
/// collide, which is enough to find where two translations line up.
const _fold = {
  'і': 'и',
  'ї': 'и',
  'ы': 'и',
  'є': 'е',
  'э': 'е',
  'ё': 'е',
  'ґ': 'г',
  'ъ': '',
  'ь': '',
  '’': '',
  "'": '',
  'ʼ': '',
};

final _word = RegExp(r'[а-яёіїєґ]+', unicode: true);

const stemLength = 4;
const _minWord = 4;

/// Hash set of stems for [text]; ints are cheaper to compare than strings.
Set<int> stemSet(String text) {
  final out = <int>{};
  for (final m in _word.allMatches(text.toLowerCase())) {
    final b = StringBuffer();
    for (final ch in m.group(0)!.split('')) {
      b.write(_fold[ch] ?? ch);
    }
    final w = b.toString();
    if (w.length < _minWord) continue;
    out.add(w.substring(0, stemLength).hashCode);
  }
  return out;
}

/// |A∩B| / sqrt(|A|·|B|), 0 when either set is empty.
double stemSimilarity(Set<int> a, Set<int> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final small = a.length <= b.length ? a : b;
  final large = identical(small, a) ? b : a;
  var common = 0;
  for (final x in small) {
    if (large.contains(x)) common++;
  }
  return common / _sqrt((a.length * b.length).toDouble());
}

double _sqrt(double x) {
  // Newton iterations avoid importing dart:math just for sqrt on tiny inputs.
  var r = x;
  for (var i = 0; i < 20 && r > 0; i++) {
    r = (r + x / r) / 2;
  }
  return r;
}

/// Languages written in Cyrillic whose words resemble Russian ones closely
/// enough for [stemSet] to compare them directly.
const cyrillicLanguages = {'ru', 'uk', 'be', 'bg', 'sr', 'mk'};

/// Whether text in [language] can be compared with Russian by [stemSet].
bool comparesDirectlyWithRussian(String language) => cyrillicLanguages.contains(
  language.toLowerCase().split(RegExp(r'[-_]')).first,
);

const _translit = {
  'а': 'a',
  'б': 'b',
  'в': 'v',
  'г': 'g',
  'д': 'd',
  'е': 'e',
  'ё': 'e',
  'ж': 's',
  'з': 's',
  'и': 'i',
  'й': 'i',
  'к': 'k',
  'л': 'l',
  'м': 'm',
  'н': 'n',
  'о': 'o',
  'п': 'p',
  'р': 'r',
  'с': 's',
  'т': 't',
  'у': 'u',
  'ф': 'f',
  'х': 'r',
  'ц': 'k',
  'ч': 'k',
  'ш': 's',
  'щ': 's',
  'ы': 'i',
  'э': 'e',
  'ю': 'u',
  'я': 'a',
};

const _latinFold = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 's',
  'ñ': 'n',
  'c': 'k',
  'q': 'k',
  'y': 'i',
  'w': 'v',
  'z': 's',
  'x': 's',
  'j': 'i',
  'h': 'r',
};

final _latinWord = RegExp(r'[a-záàâãäéèêëíìîïóòôõöúùûüçñ]+', unicode: true);
final _number = RegExp(r'\d+');

/// Hash set of rough stems for text in a Latin-script language, folded to the
/// same sound-alike alphabet as [russianAsLatinStemSet] (c/k/q, y/i/j, z/s/x,
/// h/r, accents dropped), so names and numbers collide. It is a weak signal,
/// used only when no translator can bring both texts to Russian.
Set<int> latinStemSet(String text) {
  final out = <int>{};
  for (final m in _latinWord.allMatches(text.toLowerCase())) {
    final b = StringBuffer();
    for (final ch in m.group(0)!.split('')) {
      b.write(_latinFold[ch] ?? ch);
    }
    final w = b.toString();
    if (w.length >= 4) out.add(w.substring(0, 4).hashCode);
  }
  for (final m in _number.allMatches(text)) {
    out.add('#${m.group(0)}'.hashCode);
  }
  return out;
}

/// Like [latinStemSet] for Russian text, which is transliterated first.
Set<int> russianAsLatinStemSet(String text) {
  final out = <int>{};
  for (final m in _word.allMatches(text.toLowerCase())) {
    final b = StringBuffer();
    for (final ch in m.group(0)!.split('')) {
      b.write(_translit[ch] ?? (_fold[ch] ?? ''));
    }
    final w = b.toString();
    if (w.length >= 4) out.add(w.substring(0, 4).hashCode);
  }
  for (final m in _number.allMatches(text)) {
    out.add('#${m.group(0)}'.hashCode);
  }
  return out;
}
