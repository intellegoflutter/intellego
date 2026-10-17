import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cp1251.dart';
import 'html_text_extractor.dart';

class FetchException implements Exception {
  FetchException(this.message);

  final String message;

  @override
  String toString() => 'FetchException: $message';
}

/// Downloads a web page and extracts its readable paragraphs.
class WebTextFetcher {
  WebTextFetcher({http.Client? client, HtmlTextExtractor? extractor})
      : _client = client ?? http.Client(),
        _extractor = extractor ?? const HtmlTextExtractor();

  final http.Client _client;
  final HtmlTextExtractor _extractor;

  Future<ExtractedText> fetch(Uri url) async {
    final result = _extractor.extract(await fetchHtml(url));
    if (result.paragraphs.isEmpty) {
      throw FetchException('No readable text found at $url');
    }
    return result;
  }

  /// Downloads [url] and returns the decoded HTML.
  Future<String> fetchHtml(Uri url) async {
    if (!url.hasScheme || !(url.scheme == 'http' || url.scheme == 'https')) {
      throw FetchException('Only http(s) URLs are supported: $url');
    }
    final http.Response response;
    try {
      response = await _client.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; IntellegoReader/1.0)',
        'Accept-Language': 'ru,en;q=0.5',
      });
    } catch (e) {
      throw FetchException('Request failed: $e');
    }
    if (response.statusCode != 200) {
      throw FetchException('HTTP ${response.statusCode} for $url');
    }
    return _decode(response);
  }

  String _decode(http.Response r) {
    final bytes = r.bodyBytes;
    final charset = _charset(r.headers['content-type']) ?? _sniffMeta(bytes);
    switch (charset) {
      case 'windows-1251':
      case 'cp1251':
      case 'win-1251':
        return decodeCp1251(bytes);
      default:
        return utf8.decode(bytes, allowMalformed: true);
    }
  }

  String? _charset(String? contentType) {
    if (contentType == null) return null;
    final m = RegExp(r'charset=([\w\-]+)', caseSensitive: false)
        .firstMatch(contentType);
    return m?.group(1)?.toLowerCase();
  }

  String? _sniffMeta(List<int> bytes) {
    final head = latin1.decode(bytes.take(2048).toList());
    final m = RegExp(r'charset=["\x27]?([\w\-]+)', caseSensitive: false)
        .firstMatch(head);
    return m?.group(1)?.toLowerCase();
  }
}
