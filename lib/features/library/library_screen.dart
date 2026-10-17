import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../reader/reader_screen.dart';
import 'import_screen.dart';
import 'link_audio_screen.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(booksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Intellego')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ImportScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Import text'),
      ),
      body: books.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load library: $e')),
        data: (list) => list.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                      'No texts yet. Import a Russian web page to start practicing.',
                      textAlign: TextAlign.center),
                ),
              )
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final b = list[i];
                  return Dismissible(
                    key: ValueKey(b.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Theme.of(context).colorScheme.errorContainer,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      child: const Icon(Icons.delete),
                    ),
                    onDismissed: (_) =>
                        ref.read(booksProvider.notifier).remove(b.id),
                    child: ListTile(
                      title: Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${b.practicedCount}/${b.sentences.length} sentences practiced'
                          '${b.audio == null ? '' : ' · audio linked'}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'link') {
                            Navigator.of(context).push(MaterialPageRoute<void>(
                                builder: (_) => LinkAudioScreen(bookId: b.id)));
                          } else if (v == 'delete') {
                            ref.read(booksProvider.notifier).remove(b.id);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                              value: 'link',
                              child: Text(b.audio == null
                                  ? 'Link audiobook (YouTube)'
                                  : 'Change audiobook')),
                          const PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => ReaderScreen(bookId: b.id))),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
