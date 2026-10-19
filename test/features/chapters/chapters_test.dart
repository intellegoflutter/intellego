import 'package:flutter_test/flutter_test.dart';
import 'package:intellego/data/book.dart';
import 'package:intellego/features/chapters/chapter_detection.dart';
import 'package:intellego/features/import/html_text_extractor.dart';

BookSentence s(String t, int p) =>
    BookSentence(text: t, accented: t, paragraph: p);

Book book([List<Chapter> chapters = const []]) => Book(
  id: '1',
  title: 'T',
  createdAt: DateTime.utc(2024),
  sentences: [
    s('Глава 1', 0),
    s('Он пришёл.', 1),
    s('Она ушла.', 1),
    s('II', 2),
    s('Конец.', 3),
  ],
  chapters: chapters,
);

void main() {
  test('detects headings made of a single short sentence', () {
    final found = detectChapters(book().sentences);
    expect(found, const [
      Chapter(title: 'Глава 1', sentenceIndex: 0),
      Chapter(title: 'II', sentenceIndex: 3),
    ]);
  });

  test('ignores ordinary short sentences and headings inside a paragraph', () {
    final found = detectChapters([
      s('Глава 2', 0),
      s('Он ушёл.', 0),
      s('Да.', 1),
    ]);
    expect(found, isEmpty);
  });

  test('chapterAt finds the chapter a sentence belongs to', () {
    final b = book(const [
      Chapter(title: 'A', sentenceIndex: 1),
      Chapter(title: 'B', sentenceIndex: 3),
    ]);
    expect(b.chapterAt(0), isNull);
    expect(b.chapterAt(2)?.title, 'A');
    expect(b.chapterAt(4)?.title, 'B');
  });

  test('chapters survive JSON and old books load without them', () {
    final b = book(const [Chapter(title: 'A', sentenceIndex: 1)]);
    expect(Book.fromJson(b.toJson()).chapters, b.chapters);
    expect(book().toJson().containsKey('chapters'), isFalse);
    expect(Book.fromJson(book().toJson()).chapters, isEmpty);
  });

  test('withChapters orders them and keeps one per sentence', () {
    final b = book().withChapters(const [
      Chapter(title: 'B', sentenceIndex: 3),
      Chapter(title: 'A', sentenceIndex: 1),
      Chapter(title: 'A2', sentenceIndex: 1),
    ]);
    expect([for (final c in b.chapters) c.sentenceIndex], [1, 3]);
  });

  test('appended keeps the chapters', () {
    final b = book(const [Chapter(title: 'A', sentenceIndex: 0)]);
    expect(b.appended([s('Ещё.', 4)]).chapters, b.chapters);
  });

  test('mergeChapters keeps renamed chapters', () {
    final merged = mergeChapters(const [
      Chapter(title: 'Начало', sentenceIndex: 0),
    ], detectChapters(book().sentences));
    expect([for (final c in merged) c.title], ['Начало', 'II']);
  });

  test('headings in a web page become chapters', () {
    final page = const HtmlTextExtractor().extract('''
      <html><body><article>
        <h1>Книга</h1><h2>Первая часть</h2>
        <p>Это первое длинное предложение для проверки текста.</p>
        <h2>Вторая часть</h2>
        <p>А это второе длинное предложение для проверки текста.</p>
      </article></body></html>''');
    expect(page.headings, {1, 3});
    final sentences = [
      for (var i = 0; i < page.paragraphs.length; i++) s(page.paragraphs[i], i),
    ];
    expect(
      [for (final c in chaptersFromHeadings(sentences, page.headings)) c.title],
      ['Первая часть', 'Вторая часть'],
    );
  });
}
