import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../reader/reader_screen.dart';
import '../search/library_search_screen.dart';
import '../words/practice_screen.dart';
import '../sync/sync_dialogs.dart';
import 'add_pages_dialog.dart';
import 'import_screen.dart';
import 'link_audio_screen.dart';
import 'track_picker.dart';

/// Phones and tablets ask the computer for a sync; the computer serves it.
final _isMobile = Platform.isAndroid || Platform.isIOS;

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(booksProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Intellego'),
        actions: [
          Builder(
            builder: (context) {
              final due = ref
                  .watch(vocabProvider)
                  .value
                  ?.where((e) => e.isDue(DateTime.now()))
                  .length;
              return IconButton(
                tooltip: 'Practice words',
                icon: Badge(
                  isLabelVisible: (due ?? 0) > 0,
                  label: Text('$due'),
                  child: const Icon(Icons.school_outlined),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PracticeScreen(),
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search all books',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const LibrarySearchScreen(),
              ),
            ),
          ),
          IconButton(
            icon: Icon(_isMobile ? Icons.sync : Icons.wifi_tethering),
            tooltip: _isMobile ? 'Sync now' : 'Sync with the phone',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  _isMobile ? const SyncNowDialog() : const SyncServerDialog(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const ImportScreen())),
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
                    textAlign: TextAlign.center,
                  ),
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
                      title: Text(
                        b.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${b.practicedCount}/${b.sentences.length} sentences practiced'
                        '${b.hasAudio ? ' · audio: ${audioSummary(b)}' : ''}',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'link') {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => LinkAudioScreen(bookId: b.id),
                              ),
                            );
                          } else if (v == 'part') {
                            final track = await pickTrack(
                              context,
                              b,
                              title: 'Next part of which audiobook?',
                            );
                            if (track != null && context.mounted) {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => LinkAudioScreen(
                                    bookId: b.id,
                                    addPartTo: track,
                                  ),
                                ),
                              );
                            }
                          } else if (v == 'more') {
                            showDialog<void>(
                              context: context,
                              builder: (_) => AddPagesDialog(bookId: b.id),
                            );
                          } else if (v == 'delete') {
                            ref.read(booksProvider.notifier).remove(b.id);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'link',
                            child: Text(
                              b.hasAudio
                                  ? 'Add an audiobook (another language)…'
                                  : 'Link audiobook (YouTube)',
                            ),
                          ),
                          if (b.hasAudio)
                            const PopupMenuItem(
                              value: 'part',
                              child: Text('Add next audio part…'),
                            ),
                          if (canAddPages(b))
                            const PopupMenuItem(
                              value: 'more',
                              child: Text('Add more pages…'),
                            ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ReaderScreen(bookId: b.id),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
