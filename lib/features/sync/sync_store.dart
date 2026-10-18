import 'dart:io';

import '../../data/book_repository.dart';
import '../reader/reading_position.dart';
import '../speaking/speaking_log.dart';
import 'book_bundle.dart';

/// Where one device keeps what is synchronised.
abstract class SyncStore {
  Future<List<String>> ids();

  Future<BookBundle?> load(String id);

  /// Stores [bundle] as it is (it has been merged already).
  Future<void> save(BookBundle bundle);
}

/// The books, reading-aloud results and reading positions of this device.
class LocalSyncStore implements SyncStore {
  LocalSyncStore(this._books, this._speakingDir);

  final BookRepository _books;
  final Directory _speakingDir;

  @override
  Future<List<String>> ids() async => [
    for (final b in await _books.loadAll()) b.id,
  ];

  SpeakingLog _log(String id) =>
      SpeakingLog(File('${_speakingDir.path}/$id.json'));

  @override
  Future<BookBundle?> load(String id) async {
    final book = await _books.load(id);
    if (book == null) return null;
    final log = _log(id);
    await log.load();
    return BookBundle(
      book: book,
      speaking: Map.of(log.attempts),
      position: await ReadingPosition.load(id),
    );
  }

  @override
  Future<void> save(BookBundle bundle) async {
    final id = bundle.book.id;
    await _books.save(bundle.book, keepStamp: true);
    await _log(id).replaceAll(bundle.speaking);
    await ReadingPosition.save(id, bundle.position);
  }
}
