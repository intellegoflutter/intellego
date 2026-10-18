import 'dart:convert';
import 'dart:io';

import 'book.dart';
import 'book_stamps.dart';

/// Stores each book as `<dir>/<id>.json`.
class BookRepository {
  BookRepository(this._dir);

  final Directory _dir;

  File _file(String id) => File('${_dir.path}/$id.json');

  /// The book [id], or null when there is none (or it cannot be read).
  Future<Book?> load(String id) async {
    final f = _file(id);
    if (!await f.exists()) return null;
    try {
      return Book.fromJson(
        jsonDecode(await f.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<Book>> loadAll() async {
    if (!await _dir.exists()) return [];
    final books = <Book>[];
    await for (final e in _dir.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        books.add(
          Book.fromJson(
            jsonDecode(await e.readAsString()) as Map<String, dynamic>,
          ),
        );
      } catch (_) {
        // Skip unreadable files rather than hiding the whole library.
      }
    }
    books.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return books;
  }

  /// Writes [book], stamping it as changed now unless [keepStamp] (a copy
  /// received from another device keeps the time it was changed there).
  /// Returns what was written.
  Future<Book> save(Book book, {bool keepStamp = false}) async {
    final now = DateTime.now();
    final out = keepStamp
        ? book
        : stampChanges(
            await load(book.id),
            book,
            now.millisecondsSinceEpoch,
          ).stamped(now);
    await _dir.create(recursive: true);
    await _file(out.id).writeAsString(jsonEncode(out.toJson()), flush: true);
    return out;
  }

  Future<void> delete(String id) async {
    final f = _file(id);
    if (await f.exists()) await f.delete();
  }
}
