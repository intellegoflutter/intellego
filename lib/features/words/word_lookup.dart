import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

class LookupException implements Exception {
  LookupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A part of speech with its definitions (a Wiktionary entry).
class DictEntry {
  const DictEntry(this.partOfSpeech, this.definitions);

  final String partOfSpeech;
  final List<String> definitions;
}

class WikiSummary {
  const WikiSummary({
    required this.title,
    required this.extract,
    required this.url,
    this.isDisambiguation = false,
  });

  final String title, extract;
  final Uri url;
  final bool isDisambiguation;
}

const _agent = 'IntellegoReader/1.0 (language-learning app)';

/// Looks words up in Wiktionary and Wikipedia through their public REST APIs.
class WordLookupService {
  WordLookupService({
    http.Client? client,
    this.wiktionaryHost = 'en.wiktionary.org',
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// Wiktionary edition whose definitions are shown (English by default).
  final String wiktionaryHost;

  Future<http.Response> _get(Uri url) async {
    try {
      return await _client.get(
        url,
        headers: {'User-Agent': _agent, 'Accept': 'application/json'},
      );
    } catch (e) {
      throw LookupException('Could not reach ${url.host}. Are you online?');
    }
  }

  /// Russian entries of [word] on Wiktionary; empty when there are none.
  Future<List<DictEntry>> wiktionary(String word) async {
    final r = await _get(
      Uri.https(wiktionaryHost, '/api/rest_v1/page/definition/$word'),
    );
    if (r.statusCode == 404) return const [];
    if (r.statusCode != 200) {
      throw LookupException('Wiktionary answered ${r.statusCode}.');
    }
    final json = jsonDecode(utf8.decode(r.bodyBytes));
    if (json is! Map) return const [];
    final out = <DictEntry>[];
    for (final e in (json['ru'] as List? ?? const [])) {
      final defs = <String>[];
      for (final d in (e['definitions'] as List? ?? const [])) {
        final text = _plain(d['definition'] as String? ?? '');
        if (text.isNotEmpty) defs.add(text);
      }
      if (defs.isNotEmpty) {
        out.add(DictEntry(e['partOfSpeech'] as String? ?? '', defs));
      }
    }
    return out;
  }

  /// The Russian Wikipedia article for [word], or null when there is none.
  Future<WikiSummary?> wikipedia(String word) async {
    final r = await _get(
      Uri.https('ru.wikipedia.org', '/api/rest_v1/page/summary/$word'),
    );
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) {
      throw LookupException('Wikipedia answered ${r.statusCode}.');
    }
    final json = jsonDecode(utf8.decode(r.bodyBytes));
    if (json is! Map) return null;
    final page = json['content_urls']?['desktop']?['page'] as String?;
    final extract = (json['extract'] as String? ?? '').trim();
    if (extract.isEmpty) return null;
    return WikiSummary(
      title: json['title'] as String? ?? word,
      extract: extract,
      url: Uri.parse(page ?? 'https://ru.wikipedia.org/wiki/$word'),
      isDisambiguation: json['type'] == 'disambiguation',
    );
  }

  void close() => _client.close();
}

String _plain(String html) => (html_parser.parseFragment(html).text ?? '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Pages to open in the browser for [word]: name and address.
List<(String, Uri)> lookupLinks(String word) => [
  ('Wiktionary', Uri.https('en.wiktionary.org', '/wiki/$word')),
  ('Викисловарь', Uri.https('ru.wiktionary.org', '/wiki/$word')),
  ('Wikipedia', Uri.https('ru.wikipedia.org', '/wiki/$word')),
  (
    'Google Translate',
    Uri.https('translate.google.com', '/', {
      'sl': 'ru',
      'tl': 'en',
      'text': word,
      'op': 'translate',
    }),
  ),
  (
    'Reverso',
    Uri.https('context.reverso.net', '/translation/russian-english/$word'),
  ),
];
