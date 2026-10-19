import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../reader/reader_screen.dart';
import 'book_search.dart';

/// Search in all books of the library; a hit opens the book at its sentence.
class LibrarySearchScreen extends ConsumerStatefulWidget {
  const LibrarySearchScreen({super.key});

  @override
  ConsumerState<LibrarySearchScreen> createState() =>
      _LibrarySearchScreenState();
}

class _LibrarySearchScreenState extends ConsumerState<LibrarySearchScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final books = ref.watch(booksProvider).value ?? const [];
    final ready = normalizeForSearch(_query).trim().length >= 2;
    final results = [
      if (ready)
        for (final b in books)
          for (final h in searchBook(b, _query, limit: 50)) (b, h),
    ];
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search all books',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      body: !ready
          ? const Center(child: Text('Type at least two letters.'))
          : results.isEmpty
          ? const Center(child: Text('Nothing found.'))
          : ListView.builder(
              itemCount: results.length,
              itemBuilder: (_, k) {
                final (book, h) = results[k];
                return ListTile(
                  title: Text(
                    h.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${book.title} · ${h.index + 1}'
                    '${h.field == null ? '' : ' · ${h.field}'}',
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ReaderScreen(bookId: book.id, initialIndex: h.index),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
