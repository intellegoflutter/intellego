import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intellego/features/words/vocab.dart';
import 'package:intellego/features/words/word_lookup.dart';
import 'package:intellego/features/words/word_tokens.dart';

const m = '́';

VocabEntry entry({int box = 0, DateTime? due}) => VocabEntry(
  key: 'дом',
  display: 'до${m}м',
  note: 'house',
  contexts: const [VocabContext(bookId: 'b', sentence: 3, text: 'Это дом.')],
  added: DateTime.utc(2024),
  due: due ?? DateTime.utc(2024),
  box: box,
);

void main() {
  group('tokenizeWords', () {
    test('keeps stress marks and hyphens inside words', () {
      const text = 'Он пришё${m}л домо${m}й, кто-то по-русски.';
      final words = tokenizeWords(text);
      expect(
        [for (final w in words) w.text],
        ['Он', 'пришё${m}л', 'домо${m}й', 'кто-то', 'по-русски'],
      );
      for (final w in words) {
        expect(text.substring(w.start, w.end), w.text);
      }
    });

    test('lookupForm lowers case and drops the mark but keeps ё', () {
      expect(lookupForm('Всё${m}'), 'всё');
      expect(lookupForm('До${m}м'), 'дом');
    });

    test('numbers and punctuation alone are not looked up', () {
      expect(isLookupWord('42'), isFalse);
      expect(isLookupWord('—'), isFalse);
      expect(isLookupWord('дом'), isTrue);
    });
  });

  group('WordLookupService', () {
    test('reads the Russian entries of Wiktionary', () async {
      late Uri asked;
      final service = WordLookupService(
        client: MockClient((req) async {
          asked = req.url;
          return http.Response(
            jsonEncode({
              'en': [
                {
                  'partOfSpeech': 'Noun',
                  'definitions': [
                    {'definition': 'wrong'},
                  ],
                },
              ],
              'ru': [
                {
                  'partOfSpeech': 'Noun',
                  'language': 'Russian',
                  'definitions': [
                    {
                      'definition':
                          '<a href="/wiki/house">house</a>, <i>home</i>',
                    },
                    {'definition': ''},
                  ],
                },
              ],
            }),
            200,
          );
        }),
      );
      final entries = await service.wiktionary('дом');
      expect(asked.host, 'en.wiktionary.org');
      expect(Uri.decodeFull(asked.path), endsWith('/definition/дом'));
      expect(entries.single.partOfSpeech, 'Noun');
      expect(entries.single.definitions, ['house, home']);
    });

    test('no entry is an empty list, other failures are errors', () async {
      final missing = WordLookupService(
        client: MockClient((_) async => http.Response('{}', 404)),
      );
      expect(await missing.wiktionary('xyz'), isEmpty);
      expect(await missing.wikipedia('xyz'), isNull);

      final broken = WordLookupService(
        client: MockClient((_) async => http.Response('', 500)),
      );
      expect(broken.wiktionary('дом'), throwsA(isA<LookupException>()));

      final offline = WordLookupService(
        client: MockClient((_) async => throw const SocketException('down')),
      );
      expect(offline.wikipedia('дом'), throwsA(isA<LookupException>()));
    });

    test('reads a Wikipedia summary', () async {
      final service = WordLookupService(
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'title': 'Дом',
                'extract': 'Здание.',
                'type': 'standard',
                'content_urls': {
                  'desktop': {'page': 'https://ru.wikipedia.org/wiki/Дом'},
                },
              }),
            ),
            200,
          ),
        ),
      );
      final s = await service.wikipedia('дом');
      expect(s!.title, 'Дом');
      expect(s.extract, 'Здание.');
      expect(s.isDisambiguation, isFalse);
    });

    test('links cover the usual sources', () {
      final names = [for (final l in lookupLinks('дом')) l.$1];
      expect(names, containsAll(['Wiktionary', 'Викисловарь', 'Wikipedia']));
    });
  });

  group('vocabulary', () {
    final now = DateTime.utc(2025, 1, 10);

    test('remembered words wait longer each time', () {
      var e = entry();
      e = scheduleNext(e, remembered: true, now: now);
      expect(e.box, 1);
      expect(e.due, now.add(const Duration(days: 1)));
      e = scheduleNext(e, remembered: true, now: now);
      expect(e.box, 2);
      expect(e.due, now.add(const Duration(days: 3)));
    });

    test('the last box stays the last', () {
      final e = scheduleNext(entry(box: 6), remembered: true, now: now);
      expect(e.box, 6);
      expect(e.due, now.add(const Duration(days: 90)));
    });

    test('a forgotten word starts again and is due now', () {
      final e = scheduleNext(entry(box: 4), remembered: false, now: now);
      expect(e.box, 0);
      expect(e.isDue(now), isTrue);
    });

    test('a word met in another sentence gets another context', () {
      final e = withContext(
        entry(),
        const VocabContext(bookId: 'b', sentence: 9, text: 'Мой дом.'),
      );
      expect(e.contexts.length, 2);
      expect(
        withContext(
          e,
          const VocabContext(bookId: 'b', sentence: 9, text: 'again'),
        ).contexts.length,
        2,
      );
    });

    test('round trips through the file; damage is ignored', () async {
      final dir = await Directory.systemTemp.createTemp('vocab');
      addTearDown(() => dir.delete(recursive: true));
      final file = VocabFile(File('${dir.path}/sub/vocab.json'));
      expect(await file.load(), isEmpty);
      await file.save([entry(box: 2)]);
      final back = (await file.load()).single;
      expect(back.display, 'до${m}м');
      expect(back.box, 2);
      expect(back.contexts.single.sentence, 3);
      await File('${dir.path}/sub/vocab.json').writeAsString('{oops');
      expect(await file.load(), isEmpty);
    });
  });
}
