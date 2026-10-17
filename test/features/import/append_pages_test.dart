import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intellego/data/book.dart';
import 'package:intellego/features/import/import_service.dart';
import 'package:intellego/features/import/loveread_source.dart';
import 'package:intellego/features/import/web_text_fetcher.dart';

void main() {
  final html = File('test/fixtures/loveread_page1.html').readAsStringSync();
  final requested = <String>[];
  ImportService service() => ImportService(
          fetcher: WebTextFetcher(
              client: MockClient((r) async {
        requested.add(r.url.queryParameters['p']!);
        return http.Response.bytes(utf8.encode(html), 200,
            headers: {'content-type': 'text/html; charset=utf-8'});
      })));

  setUp(requested.clear);

  test('findNextPage walks pages until the paragraph count is reached', () async {
    final src = LoveReadSource(WebTextFetcher(
        client: MockClient((r) async => http.Response.bytes(utf8.encode(html), 200,
            headers: {'content-type': 'text/html; charset=utf-8'}))),
        pageDelay: Duration.zero);
    // every fixture page has 24 paragraphs
    expect(await src.findNextPage(Uri.parse('https://loveread.ec'), 1, 1, 24), 2);
    expect(await src.findNextPage(Uri.parse('https://loveread.ec'), 1, 1, 96), 5);
    expect(await src.findNextPage(Uri.parse('https://loveread.ec'), 1, 3, 48), 5);
  });

  test('appendPages keeps old sentences, audio link and translations', () async {
    final first = await service().importLoveRead(Uri.parse('https://loveread.ec'), 18249,
        pageCount: 2);
    expect(first.nextPage, 3);
    var book = first
        .withTranslations([Translation(name: 'EN', lines: List.filled(first.sentences.length, 'x'))])
        .withAudio(LinkedAudio.single(videoId: 'v', videoTitle: 'T', sentences: [], anchors: [(1, 2)]));
    final before = book.sentences.length;
    requested.clear();

    final more = await service().appendPages(book, pageCount: 2);
    expect(requested.first, '3');
    expect(more.nextPage, 5);
    expect(more.sentences.length, before * 2);
    expect(more.sentences.first.text, book.sentences.first.text);
    expect(more.sentences[before].paragraph, book.sentences.last.paragraph + 1);
    expect(more.translations.single.lines.length, more.sentences.length);
    expect(more.translations.single.lines.last, '');
    expect(more.audio!.anchors, [(1, 2)]);
  });

  test('legacy books without nextPage are located by paragraph count', () async {
    final first = await service().importLoveRead(Uri.parse('https://loveread.ec'), 18249,
        pageCount: 4);
    final legacy = Book.fromJson(first.toJson()..remove('nextPage'));
    expect(legacy.nextPage, isNull);
    requested.clear();
    final more = await service().appendPages(legacy, pageCount: 1);
    expect(requested.last, '5'); // walked 1-4, then fetched 5
    expect(more.nextPage, 6);
  });

  test('non-loveread books cannot be extended', () async {
    final b = Book(id: '1', title: 't', createdAt: DateTime(2026), sentences: const [],
        sourceUrl: 'https://example.com/a');
    expect(() => service().appendPages(b), throwsA(isA<FetchException>()));
  });
}
