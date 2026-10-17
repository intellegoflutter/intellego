import 'package:flutter_test/flutter_test.dart';
import 'package:intellego/features/alignment/sentence_aligner.dart';

// Synthetic parallel text: sentence i shares a unique vocabulary between the
// "Russian" and "Ukrainian" version.
String ru(int i) => 'Слово${_w(i)} сказало ${_w(i + 1)} каждому ${_w(i + 2)} человеку.';
String uk(int i) => 'Слово${_w(i)} сказало ${_w(i + 1)} кожному ${_w(i + 2)} чоловіку.';
/// Unique 5-letter word per index (the aligner compares 4-letter stems).
String _w(int i) {
  const letters = 'абвгдежзклмнопрстуфхцчшщ';
  final b = StringBuffer();
  var n = i;
  for (var k = 0; k < 4; k++) {
    b.write(letters[n % letters.length]);
    n ~/= letters.length;
  }
  return '$b' 'а';
}

void main() {
  test('identical structure aligns 1-1', () {
    final a = [for (var i = 0; i < 60; i++) ru(i * 3)];
    final b = [for (var i = 0; i < 60; i++) uk(i * 3)];
    final r = alignSentences(a, b);
    expect(r.beads.every((x) => x.ruTo - x.ruFrom == 1 && x.ukTo - x.ukFrom == 1), isTrue);
    expect(r.beads.length, 60);
  });

  test('audio longer than text leaves the tail unmatched', () {
    final a = [for (var i = 0; i < 50; i++) ru(i * 3)];
    final b = [for (var i = 0; i < 80; i++) uk(i * 3)];
    final r = alignSentences(a, b);
    final matched = r.beads.where((x) => x.ruTo > x.ruFrom && x.ukTo > x.ukFrom);
    for (final x in matched.take(50)) {
      expect(x.ukFrom, x.ruFrom);
    }
  });

  test('one sentence split in two on the Ukrainian side', () {
    final a = [for (var i = 0; i < 40; i++) ru(i * 3)];
    final b = <String>[];
    for (var i = 0; i < 40; i++) {
      if (i == 20) {
        b..add('Слово${_w(60)} сказало ${_w(61)}.')..add('Кожному ${_w(62)} чоловіку.');
      } else {
        b.add(uk(i * 3));
      }
    }
    final r = alignSentences(a, b);
    final bead = r.beads.firstWhere((x) => x.ruFrom == 20);
    expect((bead.ruTo, bead.ukFrom, bead.ukTo), (21, 20, 22));
    expect(r.beads.last.ukTo, 41);
  });

  test('empty input', () {
    expect(alignSentences(const [], const ['a']).beads, isEmpty);
    expect(alignSentences(const ['a'], const []).beads, isEmpty);
  });
}
