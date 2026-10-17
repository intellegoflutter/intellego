/// Cheap Russian ↔ Ukrainian sentence similarity based on word stems.
///
/// Both languages are folded onto a common alphabet (і/ї/ы → и, є/э/ё → е,
/// ґ → г, apostrophes dropped) and every word of at least [minWord] letters
/// is reduced to its first [stemLength] letters. Cognates and names then
/// collide, which is enough to find where two translations line up.
const _fold = {
  'і': 'и', 'ї': 'и', 'ы': 'и', 'є': 'е', 'э': 'е', 'ё': 'е', 'ґ': 'г',
  'ъ': '', 'ь': '', '’': '', "'": '', 'ʼ': '',
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
