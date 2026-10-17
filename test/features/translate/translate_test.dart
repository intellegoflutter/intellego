import 'package:flutter_test/flutter_test.dart';
import 'package:intellego/data/book.dart';
import 'package:intellego/features/translate/language_codes.dart';
import 'package:intellego/features/translate/sentence_translator.dart';

class _Fake implements SentenceTranslator {
  final calls = <(String, String)>[];

  @override
  bool get supported => true;

  @override
  Future<bool> isReady(String code) async => true;

  @override
  Future<String> translate(String text, String code) async {
    calls.add((text, code));
    return '[$code] $text';
  }

  @override
  Future<void> dispose() async {}
}

Book _book(List<Translation> t) => Book(
      id: 'b',
      title: 't',
      createdAt: DateTime(2026),
      sentences: const [
        BookSentence(text: 'Привет.', accented: 'Приве́т.', paragraph: 0),
        BookSentence(text: 'Пока.', accented: 'Пока́.', paragraph: 0),
      ],
      translations: t,
    );

void main() {
  test('language labels map to codes', () {
    expect(languageCodeFor('English'), 'en');
    expect(languageCodeFor(' italiano '), 'it');
    expect(languageCodeFor('Українська'), 'uk');
    expect(languageCodeFor('IT'), 'it');
    expect(languageCodeFor('Klingon'), isNull);
    expect(languageCodeFor(''), isNull);
    expect(suggestedLanguages.every((l) => languageCodeFor(l.$1) == l.$2), isTrue);
  });

  test('only empty lines of known languages are translated', () async {
    final book = _book([
      const Translation(name: 'English', lines: ['', '']),
      const Translation(name: 'Italiano', lines: ['Ciao.', '']),
      const Translation(name: 'My notes', lines: ['', '']),
    ]);
    final fake = _Fake();
    final got = await missingTranslations(book, 0, fake);
    expect(got, {'English': '[en] Привет.'});
    expect(fake.calls, [('Привет.', 'en')]);

    final only = await missingTranslations(book, 1, fake, only: 'Italiano');
    expect(only, {'Italiano': '[it] Пока.'});
  });

  test('translated lines are written without overwriting newer ones', () {
    final book = _book([
      const Translation(name: 'English', lines: ['typed by hand', '']),
      const Translation(name: 'Italian', lines: ['', '']),
    ]);
    final next = withTranslatedLines(book, 0, {'English': 'machine', 'Italian': 'Ciao.'});
    expect(next.translations[0].lines[0], 'typed by hand');
    expect(next.translations[1].lines[0], 'Ciao.');
    expect(identical(withTranslatedLines(book, 0, {}), book), isTrue);
  });
}
