import '../../data/book.dart';
import '../chapters/chapter_detection.dart';
import '../nlp/accent/accentuator.dart';
import '../nlp/sentences/sentence_splitter.dart';
import 'loveread_source.dart';
import 'web_text_fetcher.dart';

/// Reports how many sentences have been processed (split and accented).
typedef ProcessProgress = void Function(int done, int total);

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
    ProcessProgress? onProcessProgress,
  }) async {
    final page = await _fetcher.fetch(url);
    return _build(
      title: page.title.isEmpty ? url.host : page.title,
      paragraphs: page.paragraphs,
      headings: page.headings,
      sourceUrl: url.toString(),
      accentuator: accentuator,
      stress: stress,
      yo: yo,
      onProcessProgress: onProcessProgress,
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
    ProcessProgress? onProcessProgress,
  }) async {
    final book = await _loveRead.fetchBook(
      site,
      bookId,
      firstPage: firstPage,
      pageCount: pageCount,
      onProgress: onFetchProgress,
    );
    final built = await _build(
      title: book.author == null
          ? book.title
          : '${book.title} — ${book.author}',
      paragraphs: book.paragraphs,
      sourceUrl: LoveReadSource.pageUrl(site, bookId, firstPage).toString(),
      accentuator: accentuator,
      stress: stress,
      yo: yo,
      onProcessProgress: onProcessProgress,
    );
    return built.appended(const [], nextPage: book.nextPage);
  }

  /// Appends the next [pageCount] pages (default: to the end) of a loveread
  /// book that was imported earlier. Existing sentences keep their indices,
  /// so the audio link, sync points, notes and translations stay valid.
  Future<Book> appendPages(
    Book book, {
    int? pageCount,
    Accentuator? accentuator,
    bool stress = true,
    bool yo = true,
    void Function(int done, int total)? onFetchProgress,
    ProcessProgress? onProcessProgress,
  }) async {
    final url = Uri.tryParse(book.sourceUrl ?? '');
    final id = url == null ? null : LoveReadSource.bookId(url);
    if (url == null || id == null) {
      throw FetchException(
        'Only books imported from loveread can be extended.',
      );
    }
    final site = LoveReadSource.siteOf(url);
    final paragraphs = book.sentences.isEmpty
        ? 0
        : book.sentences.last.paragraph + 1;
    final next =
        book.nextPage ??
        await _loveRead.findNextPage(
          site,
          id,
          LoveReadSource.startPage(url),
          paragraphs,
        );
    final more = await _loveRead.fetchBook(
      site,
      id,
      firstPage: next,
      pageCount: pageCount,
      onProgress: onFetchProgress,
    );
    if (more.paragraphs.isEmpty) throw FetchException('No more pages to add.');
    final offset = book.sentences.isEmpty
        ? 0
        : book.sentences.last.paragraph + 1;
    final added = await _sentences(
      more.paragraphs,
      accentuator,
      stress,
      yo,
      offset,
      onProcessProgress,
    );
    final grown = book.appended(added, nextPage: more.nextPage);
    return grown.withChapters(
      mergeChapters(grown.chapters, detectChapters(grown.sentences)),
    );
  }

  Future<List<BookSentence>> _sentences(
    List<String> paragraphs,
    Accentuator? accentuator,
    bool stress,
    bool yo,
    int paragraphOffset,
    ProcessProgress? onProgress,
  ) async {
    final out = <BookSentence>[];
    final split = _splitter.split(paragraphs.join('\n'));
    for (final s in split) {
      if (onProgress != null && out.length % 20 == 0) {
        onProgress(out.length, split.length);
        // Let the UI repaint between batches.
        await Future<void>.delayed(Duration.zero);
      }
      final accented = accentuator == null
          ? s.text
          : await accentuator.accent(s.text, stress: stress, yo: yo);
      out.add(
        BookSentence(
          text: s.text,
          accented: accented,
          paragraph: s.paragraphIndex + paragraphOffset,
        ),
      );
    }
    return out;
  }

  Future<Book> _build({
    required String title,
    required List<String> paragraphs,
    required String sourceUrl,
    required Accentuator? accentuator,
    required bool stress,
    required bool yo,
    Set<int> headings = const {},
    ProcessProgress? onProcessProgress,
  }) async {
    final sentences = await _sentences(
      paragraphs,
      accentuator,
      stress,
      yo,
      0,
      onProcessProgress,
    );
    final now = DateTime.now();
    return Book(
      id: now.microsecondsSinceEpoch.toString(),
      title: title,
      sourceUrl: sourceUrl,
      createdAt: now,
      sentences: sentences,
      chapters: mergeChapters(
        chaptersFromHeadings(sentences, headings),
        detectChapters(sentences),
      ),
    );
  }
}
