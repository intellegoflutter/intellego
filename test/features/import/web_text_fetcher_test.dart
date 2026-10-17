import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intellego/features/import/cp1251.dart';
import 'package:intellego/features/import/html_text_extractor.dart';
import 'package:intellego/features/import/web_text_fetcher.dart';

const _page = '''
<html><head><title>Сайт — Глава 1</title></head><body>
<nav><p>Меню Главная О нас</p></nav>
<h1>Глава 1</h1>
<div class="content">
  <p>Это первый абзац книги.&nbsp;Он длинный и содержит много слов для оценки.</p>
  <p>Второй абзац тоже достаточно длинный, чтобы выиграть выбор контейнера.</p>
</div>
<footer><p>© 2026</p></footer>
<script>var x = "<p>fake</p>";</script>
</body></html>
''';

List<int> _encodeCp1251(String s) => s.runes.map((r) {
      if (r < 0x80) return r;
      if (r == 0x0401) return 0xA8;
      if (r == 0x0451) return 0xB8;
      return 0xC0 + (r - 0x0410);
    }).toList();

void main() {
  test('extractor keeps main paragraphs, drops chrome', () {
    final r = const HtmlTextExtractor().extract(_page);
    expect(r.title, 'Глава 1');
    expect(r.paragraphs, hasLength(2));
    expect(r.paragraphs.first, startsWith('Это первый абзац'));
    expect(r.paragraphs.join(), isNot(contains('Меню')));
    expect(r.paragraphs.join(), isNot(contains('fake')));
  });

  test('cp1251 decoder', () {
    expect(decodeCp1251(_encodeCp1251('Привет, ёлка')), 'Привет, ёлка');
  });

  test('fetcher decodes utf-8', () async {
    final client = MockClient((_) async => http.Response.bytes(
        utf8.encode(_page), 200,
        headers: {'content-type': 'text/html; charset=utf-8'}));
    final r = await WebTextFetcher(client: client)
        .fetch(Uri.parse('https://example.com/b'));
    expect(r.paragraphs, hasLength(2));
  });

  test('fetcher decodes windows-1251 from header', () async {
    final body = _encodeCp1251(
        '<html><body><p>Ёлка стоит в углу комнаты и ждёт праздника.</p></body></html>');
    final client = MockClient((_) async => http.Response.bytes(body, 200,
        headers: {'content-type': 'text/html; charset=windows-1251'}));
    final r = await WebTextFetcher(client: client)
        .fetch(Uri.parse('https://example.com/b'));
    expect(r.paragraphs.single, startsWith('Ёлка стоит'));
  });

  test('fetcher errors', () async {
    final notFound = MockClient((_) async => http.Response('', 404));
    expect(() => WebTextFetcher(client: notFound).fetch(Uri.parse('https://a.b')),
        throwsA(isA<FetchException>()));
    expect(() => WebTextFetcher(client: notFound).fetch(Uri.parse('ftp://a.b')),
        throwsA(isA<FetchException>()));
  });
}
