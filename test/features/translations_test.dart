import 'package:flutter_test/flutter_test.dart';
import 'package:intellego/data/book.dart';

void main() {
  Book base() => Book(
    id: '1',
    title: 't',
    createdAt: DateTime(2026),
    sentences: const [
      BookSentence(text: 'a', accented: 'a', paragraph: 0),
      BookSentence(text: 'b', accented: 'b', paragraph: 0),
      BookSentence(text: 'c', accented: 'c', paragraph: 1),
    ],
  );

  test('translations round trip and keep other edits', () {
    var book = base().withTranslations([
      Translation(name: 'English', lines: ['one', '', 'three'], visible: false),
    ]);
    book = book.withSentences(
      [...book.sentences]..[0] = book.sentences[0].copyWith(practiced: true),
    );
    final back = Book.fromJson(book.toJson());
    expect(back.translations.single.name, 'English');
    expect(back.translations.single.visible, isFalse);
    expect(back.translations.single.lines, ['one', '', 'three']);
    expect(back.translations.single.filled, 2);
    expect(back.sentences[0].practiced, isTrue);
  });

  test('withLine trims and does not mutate the original', () {
    const t = Translation(name: 'ES', lines: ['', '', '']);
    final u = t.withLine(1, '  hola  ');
    expect(u.lines, ['', 'hola', '']);
    expect(t.lines, ['', '', '']);
  });

  test('old books without translations still load', () {
    final json = base().toJson()..remove('translations');
    expect(Book.fromJson(json).translations, isEmpty);
  });

  test('translations survive audio and sentence updates', () {
    final book = base().withTranslations([
      const Translation(name: 'EN', lines: ['x', 'y', 'z']),
    ]);
    expect(book.withSentences(book.sentences).translations, hasLength(1));
    expect(book.withTracks(const []).translations, hasLength(1));
  });
}
