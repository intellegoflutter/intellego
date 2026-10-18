import 'package:flutter_test/flutter_test.dart';
import 'package:intellego/features/speaking/pronunciation_comparer.dart';

String _show(Comparison c) => c.words
    .map(
      (w) => switch (w.status) {
        WordStatus.correct => w.expected!,
        WordStatus.misheard => '${w.expected}→${w.heard}',
        WordStatus.missed => '-${w.expected}',
        WordStatus.extra => '+${w.heard}',
      },
    )
    .join(' ');

void main() {
  const sentence = 'Нача́ла она́ расска́зывать о свое́й жи́зни.';

  test('perfect reading ignores case, punctuation and stress marks', () {
    final c = compareWords(
      accented: sentence,
      heard: 'начала она рассказывать о своей жизни',
    );
    expect(c.perfect, isTrue);
    expect(c.score, 1);
    expect(c.problems, isEmpty);
  });

  test('ё is heard as е and vice versa', () {
    final c = compareWords(
      accented: 'Всё прошло лёгко.',
      heard: 'все прошло легко',
    );
    expect(c.perfect, isTrue);
  });

  test('a skipped word is reported as missed', () {
    final c = compareWords(
      accented: sentence,
      heard: 'начала она рассказывать о жизни',
    );
    expect(_show(c), 'Нача́ла она́ расска́зывать о -свое́й жи́зни');
    expect(c.problems.single.status, WordStatus.missed);
    expect(c.score, closeTo(5 / 6, 1e-9));
  });

  test('a garbled word is a near miss, a different word is not', () {
    final near = compareWords(
      accented: sentence,
      heard: 'начала она рассказывать о своей жизне',
    );
    final miss = near.problems.single;
    expect(miss.status, WordStatus.misheard);
    expect(miss.heard, 'жизне');
    expect(miss.nearMiss, isTrue);

    final far = compareWords(
      accented: sentence,
      heard: 'начала она рассказывать о своей собаке',
    );
    expect(far.problems.single.nearMiss, isFalse);
  });

  test('extra words are listed but do not lower the score', () {
    final c = compareWords(
      accented: sentence,
      heard: 'ну начала она рассказывать о своей жизни',
    );
    expect(c.words.first.status, WordStatus.extra);
    expect(c.words.first.heard, 'ну');
    expect(c.score, 1);
    expect(c.perfect, isFalse);
  });

  test(
    'hyphenated words are compared part by part, dashes and digits ignored',
    () {
      final c = compareWords(
        accented: '– Кто́-нибу́дь зна́ет, что в 1990 году́?',
        heard: 'кто нибудь знает что в году',
      );
      expect(c.perfect, isTrue);
      expect(c.expectedCount, 6);
    },
  );

  test('empty transcript misses every word', () {
    final c = compareWords(accented: sentence, heard: '');
    expect(c.words.every((w) => w.status == WordStatus.missed), isTrue);
    expect(c.score, 0);
  });

  test('stress helpers', () {
    expect(stressedSyllable('расска́зывать'), 2);
    expect(stressedSyllable('жи́зни'), 1);
    expect(stressedSyllable('свое́й'), 2);
    expect(stressedSyllable('всё'), 1);
    expect(stressedSyllable('о'), isNull);
    expect(syllableCount('расска́зывать'), 4);
  });
}
