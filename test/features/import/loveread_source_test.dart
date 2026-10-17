import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intellego/features/import/import_target.dart';
import 'package:intellego/features/import/loveread_source.dart';
import 'package:intellego/features/import/web_text_fetcher.dart';

void main() {
  final html = File('test/fixtures/loveread_page1.html').readAsStringSync();
  final site = Uri.parse('https://loveread.ec');

  test('parses MsoNormal paragraphs, title, author and page count', () {
    final p = LoveReadSource(WebTextFetcher()).parsePage(html);
    expect(p.title, 'Клан Пещерного Медведя');
    expect(p.author, 'Джин М. Ауэл');
    expect(p.lastPage, 152);
    expect(p.paragraphs.first, 'Тебе, Рэй.');
    expect(p.paragraphs, hasLength(24));
    expect(p.paragraphs.join(), isNot(contains('Глава 1')));
  });

  test('book id and page come from the URL', () {
    final u = Uri.parse('https://loveread.ec/read_book.php?id=18249&p=7');
    expect(LoveReadSource.bookId(u), 18249);
    expect(LoveReadSource.startPage(u), 7);
    expect(LoveReadSource.bookId(Uri.parse('https://example.com/?id=3')), isNull);
    expect(LoveReadSource.pageUrl(site, 18249, 3).toString(),
        'https://loveread.ec/read_book.php?id=18249&p=3');
  });

  test('fetchBook walks the requested pages', () async {
    final requested = <String>[];
    final client = MockClient((r) async {
      requested.add(r.url.queryParameters['p']!);
      return http.Response.bytes(_utf8(html), 200,
          headers: {'content-type': 'text/html; charset=utf-8'});
    });
    final src = LoveReadSource(WebTextFetcher(client: client), pageDelay: Duration.zero);
    final progress = <String>[];
    final book = await src.fetchBook(site, 18249,
        firstPage: 5, pageCount: 3, onProgress: (d, t) => progress.add('$d/$t'));
    expect(requested, ['5', '6', '7']);
    expect(progress, ['1/3', '2/3', '3/3']);
    expect(book.paragraphs, hasLength(24 * 3));
  });

  test('input parsing', () {
    final t = parseImportInput('18249', site: site) as LoveReadTarget;
    expect((t.bookId, t.firstPage, t.site.host), (18249, 1, 'loveread.ec'));
    final u = parseImportInput('https://loveread.ec/read_book.php?id=5&p=4',
        site: Uri.parse('https://other.example')) as LoveReadTarget;
    expect((u.bookId, u.firstPage, u.site.host), (5, 4, 'loveread.ec'));
    expect(parseImportInput('https://example.com/a', site: site), isA<WebPageTarget>());
    final bare = parseImportInput('Loveread.ec/read_book.php?id=7&p=2', site: Uri.parse('https://other.example'))
        as LoveReadTarget;
    expect((bare.bookId, bare.firstPage, bare.site.host), (7, 2, 'loveread.ec'));
    final path = parseImportInput('read_book.php?id=9', site: site) as LoveReadTarget;
    expect((path.bookId, path.site.host), (9, 'loveread.ec'));
    expect(parseImportInput('/read_book.php?id=9', site: site), isA<LoveReadTarget>());
    expect(parseImportInput('  ', site: site), isNull);
    expect(parseImportInput('not a url', site: site), isNull);
    expect(inputPrefix(site), 'https://loveread.ec/read_book.php?id=');
  });
}

List<int> _utf8(String s) => const Utf8Encoder().convert(s);
