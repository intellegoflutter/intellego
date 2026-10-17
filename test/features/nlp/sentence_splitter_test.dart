import 'package:flutter_test/flutter_test.dart';
import 'package:intellego/features/nlp/sentences/sentence_splitter.dart';

List<String> split(String s) =>
    const SentenceSplitter().split(s).map((e) => e.text).toList();

void main() {
  test('basic sentences', () {
    expect(split('Он пришёл домой. Она ждала! Кто там? Никто.'),
        ['Он пришёл домой.', 'Она ждала!', 'Кто там?', 'Никто.']);
  });

  test('initials and title abbreviations do not split', () {
    expect(split('А. С. Пушкин родился в 1799 г. в Москве. Он был поэтом.'),
        ['А. С. Пушкин родился в 1799 г. в Москве.', 'Он был поэтом.']);
    expect(split('Мы жили на ул. Ленина. Дом был старый.'),
        ['Мы жили на ул. Ленина.', 'Дом был старый.']);
  });

  test('terminal abbreviation splits before capital letter', () {
    expect(split('Там были яблоки, груши и т. д. Потом мы ушли.'),
        ['Там были яблоки, груши и т. д.', 'Потом мы ушли.']);
    expect(split('Там были яблоки, груши и т.д. и мы ели.'),
        ['Там были яблоки, груши и т.д. и мы ели.']);
  });

  test('quotes and brackets stay with their sentence', () {
    expect(split('Он сказал: «Иду домой.» Потом вышел.'),
        ['Он сказал: «Иду домой.»', 'Потом вышел.']);
    expect(split('Она закричала: «Стой!» Он остановился.'),
        ['Она закричала: «Стой!»', 'Он остановился.']);
  });

  test('ellipsis only splits before a capital', () {
    expect(split('Я думал… и решил уйти. Но остался…  Потом пришла она.'),
        ['Я думал… и решил уйти.', 'Но остался…', 'Потом пришла она.']);
  });

  test('dialogue dashes', () {
    expect(split('— Привет, — сказал он. — Как дела?'),
        ['— Привет, — сказал он.', '— Как дела?']);
  });

  test('decimals and numbers', () {
    expect(split('Это стоит 3.5 рубля. Дорого.'),
        ['Это стоит 3.5 рубля.', 'Дорого.']);
  });

  test('paragraphs always split and carry an index', () {
    final r = const SentenceSplitter().split('Первый абзац\n\nВторой. Ещё.');
    expect(r.map((e) => e.text), ['Первый абзац', 'Второй.', 'Ещё.']);
    expect(r.map((e) => e.paragraphIndex), [0, 1, 1]);
  });

  test('empty input', () {
    expect(split('  \n '), isEmpty);
  });
}
