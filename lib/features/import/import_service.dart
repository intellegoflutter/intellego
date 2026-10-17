import '../../data/book.dart';
import '../nlp/accent/accentuator.dart';
import '../nlp/sentences/sentence_splitter.dart';
import 'loveread_source.dart';
import 'web_text_fetcher.dart';

class ImportService {
  ImportService({
    required this._fetcher,
    this._splitter = const SentenceSplitter(),
  }) : _loveRead = LoveReadSource(_fetcher);

  final WebTextFetcher _fetcher;
  final LoveReadSource _loveRead;
  final SentenceSplitter _splitter;

  /// Fetches [url], splits it into sentences and, when [accentuator] is
  /// given, adds stress marks / ё according to [stress] and [yo].
  Future<Book> importUrl(
    Uri url, {
    Accentuator? accentuator,
    bool stress = true,
    bool yo = true,
  }) async {
    final page = await _fetcher.fetch(url);
    return _build(
      title: page.title.isEmpty ? url.host : page.title,
      paragraphs: page.paragraphs,
      sourceUrl: url.toString(),
      accentuator: accentuator,
      stress: stress,
      yo: yo,
    );
  }

  /// Imports a loveread.* book. [site] is e.g. `https://loveread.ec`.
  /// Reads [pageCount] pages (default: to the end) starting at [firstPage].
  Future<Book> importLoveRead(
    Uri site,
    int bookId, {
    int firstPage = 1,
    int? pageCount,
    Accentuator? accentuator,
    bool stress = true,
    bool yo = true,
    void Function(int done, int total)? onFetchProgress,
  }) async {
    final book = await _loveRead.fetchBook(site, bookId,
        firstPage: firstPage, pageCount: pageCount, onProgress: onFetchProgress);
    return _build(
      title: book.author == null ? book.title : '${book.title} — ${book.author}',
      paragraphs: book.paragraphs,
      sourceUrl: LoveReadSource.pageUrl(site, bookId, firstPage).toString(),
      accentuator: accentuator,
      stress: stress,
      yo: yo,
    );
  }

  Future<Book> _build({
    required String title,
    required List<String> paragraphs,
    required String sourceUrl,
    required Accentuator? accentuator,
    required bool stress,
    required bool yo,
  }) async {
    final split = _splitter.split(paragraphs.join('\n'));
    final sentences = <BookSentence>[];
    for (final s in split) {
      final accented = accentuator == null
          ? s.text
          : await accentuator.accent(s.text, stress: stress, yo: yo);
      sentences.add(BookSentence(
          text: s.text, accented: accented, paragraph: s.paragraphIndex));
    }
    final now = DateTime.now();
    return Book(
      id: now.microsecondsSinceEpoch.toString(),
      title: title,
      sourceUrl: sourceUrl,
      createdAt: now,
      sentences: sentences,
    );
  }
}
