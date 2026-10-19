import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/book.dart';
import 'book_search.dart';

/// Search inside one book. Pops with the sentence index to go to.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final book = ref
        .watch(booksProvider)
        .value
        ?.where((b) => b.id == widget.bookId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search this book',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: book == null ? const SizedBox.shrink() : _results(book),
    );
  }

  Widget _results(Book book) {
    final chapters = searchChapters(book, _query);
    final hits = searchBook(book, _query);
    if (normalizeForSearch(_query).trim().length < 2) {
      return const Center(child: Text('Type at least two letters.'));
    }
    if (hits.isEmpty && chapters.isEmpty) {
      return const Center(child: Text('Nothing found.'));
    }
    final theme = Theme.of(context);
    return ListView(
      children: [
        for (final c in chapters)
          ListTile(
            leading: const Icon(Icons.bookmark_outline),
            title: Text(c.title),
            subtitle: Text('Chapter · sentence ${c.sentenceIndex + 1}'),
            onTap: () => Navigator.pop(context, c.sentenceIndex),
          ),
        for (final h in hits)
          ListTile(
            title: Text.rich(_highlight(h, theme)),
            subtitle: Text(
              '${h.index + 1}${h.field == null ? '' : ' · ${h.field}'}'
              '${book.chapterAt(h.index) == null ? '' : ' · ${book.chapterAt(h.index)!.title}'}',
            ),
            onTap: () => Navigator.pop(context, h.index),
          ),
      ],
    );
  }

  /// The hit with a little context around the match, the match in bold.
  TextSpan _highlight(SearchHit h, ThemeData theme) {
    const around = 60;
    final from = (h.start - around).clamp(0, h.text.length);
    final to = (h.end + around).clamp(0, h.text.length);
    return TextSpan(
      children: [
        TextSpan(
          text: '${from > 0 ? '…' : ''}${h.text.substring(from, h.start)}',
        ),
        TextSpan(
          text: h.text.substring(h.start, h.end),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            backgroundColor: theme.colorScheme.tertiaryContainer,
          ),
        ),
        TextSpan(
          text:
              '${h.text.substring(h.end, to)}${to < h.text.length ? '…' : ''}',
        ),
      ],
    );
  }
}
