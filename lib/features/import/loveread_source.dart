import 'package:html/parser.dart' as html_parser;

import 'web_text_fetcher.dart';

/// One parsed page of a loveread.* book.
class LoveReadPage {
  const LoveReadPage({
    required this.title,
    required this.author,
    required this.paragraphs,
    required this.lastPage,
  });

  final String title;
  final String? author;
  final List<String> paragraphs;

  /// Highest page number found in the pagination bar (1 when absent).
  final int lastPage;
}

class LoveReadBook {
  const LoveReadBook({required this.title, required this.author, required this.paragraphs});

  final String title;
  final String? author;
  final List<String> paragraphs;
}

/// Reads books from loveread.* (e.g. `https://loveread.ec/read_book.php?id=18249&p=1`).
/// Only `<p class=MsoNormal>` paragraphs are kept; headings, images and
/// navigation are dropped.
class LoveReadSource {
  LoveReadSource(this._fetcher, {this.pageDelay = const Duration(milliseconds: 250)});

  final WebTextFetcher _fetcher;
  final Duration pageDelay;

  /// Book id of a loveread URL, or null when [url] is not one.
  static int? bookId(Uri url) {
    if (!url.host.contains('loveread')) return null;
    return int.tryParse(url.queryParameters['id'] ?? '');
  }

  /// Page number requested by [url] (`p=`), 1 when absent.
  static int startPage(Uri url) =>
      int.tryParse(url.queryParameters['p'] ?? '') ?? 1;

  static Uri pageUrl(Uri site, int id, int page) => Uri(
        scheme: site.scheme,
        host: site.host,
        port: site.hasPort ? site.port : null,
        path: '/read_book.php',
        queryParameters: {'id': '$id', 'p': '$page'},
      );

  /// Scheme + host of [url], the part worth remembering between imports.
  static Uri siteOf(Uri url) =>
      Uri(scheme: url.scheme, host: url.host, port: url.hasPort ? url.port : null);

  static final _ws = RegExp(r'\s+');
  static final _pageParam = RegExp(r'[?&]p=(\d+)');

  LoveReadPage parsePage(String html) {
    final doc = html_parser.parse(html);
    final paragraphs = <String>[];
    for (final p in doc.querySelectorAll('p.MsoNormal')) {
      final text = p.text.replaceAll(' ', ' ').replaceAll('­', '').replaceAll(_ws, ' ').trim();
      if (text.isNotEmpty) paragraphs.add(text);
    }
    var last = 1;
    for (final a in doc.querySelectorAll('.navigation a')) {
      final n = int.tryParse(_pageParam.firstMatch(a.attributes['href'] ?? '')?.group(1) ?? '');
      if (n != null && n > last) last = n;
    }
    // "<title>Name – страница 1 | Author | Читать онлайн на LoveRead.ec</title>"
    final parts = (doc.querySelector('title')?.text ?? '').split('|');
    final title = parts.first.split(RegExp(r'\s[–-]\sстраница')).first.trim();
    final author = parts.length > 1 ? parts[1].trim() : null;
    return LoveReadPage(
      title: title,
      author: author == null || author.isEmpty ? null : author,
      paragraphs: paragraphs,
      lastPage: last,
    );
  }

  /// Fetches [pageCount] pages (all remaining pages when null) starting at
  /// [firstPage]. [onProgress] reports (pagesDone, pagesTotal).
  Future<LoveReadBook> fetchBook(
    Uri site,
    int id, {
    int firstPage = 1,
    int? pageCount,
    void Function(int done, int total)? onProgress,
  }) async {
    final first = parsePage(await _fetcher.fetchHtml(pageUrl(site, id, firstPage)));
    final lastAvailable = first.lastPage;
    final lastWanted = pageCount == null
        ? lastAvailable
        : (firstPage + pageCount - 1).clamp(firstPage, lastAvailable);
    final total = lastWanted - firstPage + 1;
    final paragraphs = [...first.paragraphs];
    onProgress?.call(1, total);
    for (var page = firstPage + 1; page <= lastWanted; page++) {
      await Future<void>.delayed(pageDelay);
      paragraphs.addAll(
          parsePage(await _fetcher.fetchHtml(pageUrl(site, id, page))).paragraphs);
      onProgress?.call(page - firstPage + 1, total);
    }
    if (paragraphs.isEmpty) {
      throw FetchException('No <p class=MsoNormal> text found for book $id');
    }
    return LoveReadBook(title: first.title, author: first.author, paragraphs: paragraphs);
  }
}
