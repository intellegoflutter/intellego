import 'dart:convert';
import 'dart:io';

import 'book.dart';

/// Stores each book as `<dir>/<id>.json`.
class BookRepository {
  BookRepository(this._dir);

  final Directory _dir;

  File _file(String id) => File('${_dir.path}/$id.json');

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

  Future<void> save(Book book) async {
    await _dir.create(recursive: true);
    await _file(book.id).writeAsString(jsonEncode(book.toJson()), flush: true);
  }

  Future<void> delete(String id) async {
    final f = _file(id);
    if (await f.exists()) await f.delete();
  }
}
