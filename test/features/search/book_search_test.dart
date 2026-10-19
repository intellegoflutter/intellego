import 'package:flutter_test/flutter_test.dart';
import 'package:intellego/data/book.dart';
import 'package:intellego/features/search/book_search.dart';

const m = '́';

BookSentence s(String t) => BookSentence(text: t, accented: t, paragraph: 0);

final book = Book(
  id: '1',
  title: 'T',
  createdAt: DateTime.utc(2024),
  sentences: [s('Он пришёл домо${m}й.'), s('Всё хорошо.'), s('Ночь.')],
  translations: const [
    Translation(name: 'Italiano', lines: ['Venne a casa.', '', 'Notte.']),
  ],
  chapters: const [Chapter(title: 'Глава Первая', sentenceIndex: 0)],
);

void main() {
  test('ignores stress marks, case and ё', () {
    expect(searchBook(book, 'ДОМОЙ').single.index, 0);
    expect(searchBook(book, 'пришел').single.index, 0);
    expect(searchBook(book, 'всё').single.index, 1);
    expect(searchBook(book, 'всё${m}').single.index, 1);
  });

  test('the match range points into the accented text', () {
    final h = searchBook(book, 'домой').single;
    expect(h.text.substring(h.start, h.end), 'домо${m}й');
  });

  test('searches translations unless told not to', () {
    final h = searchBook(book, 'casa');
    expect(h.single.field, 'Italiano');
    expect(searchBook(book, 'casa', inTranslations: false), isEmpty);
  });

  test('short queries find nothing and limit is respected', () {
    expect(searchBook(book, 'о'), isEmpty);
    expect(searchBook(book, 'ночь', limit: 0), isEmpty);
  });

  test('finds chapters by title', () {
    expect(searchChapters(book, 'первая').single.sentenceIndex, 0);
    expect(searchChapters(book, 'вторая'), isEmpty);
  });
}
