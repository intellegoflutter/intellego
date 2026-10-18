import 'package:flutter_test/flutter_test.dart';
import 'package:intellego/features/nlp/accent/accentuator.dart';
import 'package:intellego/features/nlp/accent/dictionary_accentuator.dart';
import 'package:intellego/features/nlp/accent/stress_dictionary.dart';

const _m = stressMark;

DictionaryAccentuator _make() => DictionaryAccentuator(
  stress: const MapStressDictionary({
    'мама': 1,
    'молоко': 5,
    'замок': 1, // also an omograph: must stay unmarked
    'кто-нибудь': 5,
    'книга': 2,
    'ёлка': 0,
  }),
  yoWords: {'елка': 'ёлка', 'мед': 'мёд'},
  omographs: {'замок'},
  yoHomographs: {'все'},
);

void main() {
  final acc = _make();

  test('adds stress mark after the stressed vowel', () async {
    expect(
      await acc.accent('Мама купила молоко.'),
      'Ма$_mма купила молоко$_m.',
    );
  });

  test('keeps capitalization and punctuation', () async {
    expect(await acc.accent('«Книга!»'), '«Кни$_mга!»');
  });

  test('restores ё without extra stress mark', () async {
    expect(await acc.accent('Елка'), 'Ёлка');
    expect(await acc.accent('мед'), 'мёд');
  });

  test('homographs and unknown words stay unmarked', () async {
    expect(await acc.accent('замок'), 'замок');
    expect(await acc.accent('все'), 'все');
    expect(await acc.accent('абракадабра'), 'абракадабра');
  });

  test('monosyllables are not marked', () async {
    expect(await acc.accent('мед'), isNot(contains(_m)));
  });

  test('hyphenated words', () async {
    expect(await acc.accent('кто-нибудь'), 'кто-ни$_mбудь');
  });

  test('already marked words are untouched', () async {
    expect(await acc.accent('ма$_mма'), 'ма$_mма');
  });

  test('flags can disable stress or ё independently', () async {
    expect(await acc.accent('мама елка', stress: false), 'мама ёлка');
    expect(await acc.accent('мама елка', yo: false), 'ма$_mма елка');
  });

  test('latin and digits pass through', () async {
    expect(await acc.accent('Windows 11, мама'), 'Windows 11, ма$_mма');
  });
}
