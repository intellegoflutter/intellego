import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/book.dart';
import 'chapter_detection.dart';

/// Lists the chapters of a book. Pops with the sentence index to go to.
class ChaptersSheet extends ConsumerWidget {
  const ChaptersSheet({super.key, required this.bookId, required this.current});

  final String bookId;

  /// Sentence the reader is at, to mark the current chapter.
  final int current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref
        .watch(booksProvider)
        .value
        ?.where((b) => b.id == bookId)
        .firstOrNull;
    if (book == null) return const SizedBox.shrink();
    final chapters = book.chapters;
    final here = book.chapterAt(current);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Chapters'),
              trailing: TextButton.icon(
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Detect'),
                onPressed: () => _detect(context, ref, book),
              ),
            ),
            const Divider(height: 1),
            if (chapters.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No chapters yet. Use Detect to look for headings such as '
                  '"Глава 1", or add one from a sentence\'s menu.',
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: chapters.length,
                  itemBuilder: (_, k) {
                    final c = chapters[k];
                    final end = k + 1 < chapters.length
                        ? chapters[k + 1].sentenceIndex
                        : book.sentences.length;
                    final total = end - c.sentenceIndex;
                    var done = 0;
                    for (var i = c.sentenceIndex; i < end; i++) {
                      if (book.sentences[i].practiced) done++;
                    }
                    return ListTile(
                      selected: c == here,
                      title: Text(c.title),
                      subtitle: Text(
                        'Sentence ${c.sentenceIndex + 1} · $done of $total practiced',
                      ),
                      onTap: () => Navigator.pop(context, c.sentenceIndex),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _detect(BuildContext context, WidgetRef ref, Book book) async {
    final found = detectChapters(book.sentences);
    final merged = mergeChapters(book.chapters, found);
    final added = merged.length - book.chapters.length;
    if (added > 0) {
      await ref
          .read(booksProvider.notifier)
          .updateBook(book.withChapters(merged));
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added > 0 ? 'Found $added chapters.' : 'No new chapter headings.',
        ),
      ),
    );
  }
}

/// Asks for a chapter title; null when cancelled.
Future<String?> askChapterTitle(
  BuildContext context, {
  required String initial,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Chapter title'),
      content: TextField(
        controller: controller,
        autofocus: true,
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}
