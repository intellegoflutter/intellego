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
  Future<String> translate(String text, String code) =>
      translateBetween(text, 'ru', code);

  @override
  Future<String> translateBetween(String text, String from, String to) async {
    calls.add((text, to));
    return '[$to] $text';
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
    expect(
      suggestedLanguages.every((l) => languageCodeFor(l.$1) == l.$2),
      isTrue,
    );
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
    final next = withTranslatedLines(book, 0, {
      'English': 'machine',
      'Italian': 'Ciao.',
    });
    expect(next.translations[0].lines[0], 'typed by hand');
    expect(next.translations[1].lines[0], 'Ciao.');
    expect(identical(withTranslatedLines(book, 0, {}), book), isTrue);
  });

  group('translateLanguage', () {
    Book book = _book([
      const Translation(name: 'Italian', lines: ['', '']),
      const Translation(name: 'English', lines: ['', '']),
    ]);
    final saves = <Book>[];

    Future<int> run(
      _Fake fake, {
      bool Function()? cancelled,
      int saveEvery = 25,
      void Function(int, int)? onProgress,
    }) => translateLanguage(
      bookId: 'b',
      name: 'Italian',
      translator: fake,
      latest: () => book,
      save: (b) async {
        saves.add(b);
        book = b;
      },
      cancelled: cancelled,
      saveEvery: saveEvery,
      onProgress: onProgress,
    );

    setUp(() {
      saves.clear();
      book = _book([
        const Translation(name: 'Italian', lines: ['', '']),
        const Translation(name: 'English', lines: ['', '']),
      ]);
    });

    test('fills one language only and reports progress', () async {
      final progress = <(int, int)>[];
      final added = await run(
        _Fake(),
        onProgress: (d, t) => progress.add((d, t)),
      );
      expect(added, 2);
      expect(book.translations[0].lines, ['[it] Привет.', '[it] Пока.']);
      expect(book.translations[1].lines, ['', '']);
      expect(progress.first, (0, 2));
      expect(progress.last, (2, 2));
      expect(saves, hasLength(1));
    });

    test('lines that are already there are not translated again', () async {
      book = _book([
        const Translation(name: 'Italian', lines: ['Ciao.', '']),
      ]);
      final fake = _Fake();
      expect(await run(fake), 1);
      expect(fake.calls, [('Пока.', 'it')]);
      expect(book.translations.single.lines, ['Ciao.', '[it] Пока.']);
    });

    test('stopping keeps what was translated', () async {
      var stop = false;
      final fake = _Fake();
      final added = await run(
        fake,
        saveEvery: 1,
        cancelled: () => stop,
        onProgress: (done, _) => stop = done >= 1,
      );
      expect(added, 1);
      expect(book.translations[0].lines, ['[it] Привет.', '']);
    });

    test('work done before a failure is saved', () async {
      final failing = _FailAfter(1);
      await expectLater(run(failing), throwsStateError);
      expect(book.translations[0].lines, ['[it] Привет.', '']);
    });

    test('a language without a known code is refused', () async {
      book = _book([
        const Translation(name: 'My notes', lines: ['', '']),
      ]);
      await expectLater(
        translateLanguage(
          bookId: 'b',
          name: 'My notes',
          translator: _Fake(),
          latest: () => book,
          save: (_) async {},
        ),
        throwsArgumentError,
      );
    });
  });
}

class _FailAfter extends _Fake {
  _FailAfter(this.ok);

  int ok;

  @override
  Future<String> translateBetween(String text, String from, String to) async {
    if (ok-- <= 0) throw StateError('model missing');
    return super.translateBetween(text, from, to);
  }
}
