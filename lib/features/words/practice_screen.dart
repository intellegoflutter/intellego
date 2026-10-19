import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../reader/reader_screen.dart';
import 'vocab.dart';
import 'word_list_screen.dart';

/// Reviews the saved words that are due, one card at a time.
class PracticeScreen extends ConsumerStatefulWidget {
  const PracticeScreen({super.key});

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> {
  /// Keys still to review in this session; forgotten words go to the end.
  List<String>? _queue;
  var _shown = false;
  var _reviewed = 0;

  List<String> _due(List<VocabEntry> all, {bool everything = false}) {
    final now = DateTime.now();
    final due = [
      for (final e in all)
        if (everything || e.isDue(now)) e,
    ]..sort((a, b) => a.due.compareTo(b.due));
    return [for (final e in due) e.key];
  }

  Future<void> _answer(String key, {required bool remembered}) async {
    await ref.read(vocabProvider.notifier).review(key, remembered: remembered);
    setState(() {
      final queue = [..._queue!]..removeAt(0);
      if (!remembered) queue.add(key);
      _queue = queue;
      _shown = false;
      _reviewed++;
    });
  }

  void _openContext(VocabContext c) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ReaderScreen(bookId: c.bookId, initialIndex: c.sentence),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(vocabProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Practice words'),
        actions: [
          IconButton(
            tooltip: 'All words',
            icon: const Icon(Icons.list),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const WordListScreen()),
            ),
          ),
        ],
      ),
      body: all == null
          ? const Center(child: CircularProgressIndicator())
          : _body(context, all),
    );
  }

  Widget _body(BuildContext context, List<VocabEntry> all) {
    if (all.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No words yet. Tap a word in a sentence and choose Add to practice.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final queue = _queue ??= _due(all);
    if (queue.isEmpty) return _done(context, all);
    final entry = all.where((e) => e.key == queue.first).firstOrNull;
    if (entry == null) {
      // Removed meanwhile.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _queue = [...queue]..removeAt(0));
        }
      });
      return const SizedBox.shrink();
    }
    return _card(context, entry, queue.length);
  }

  Widget _done(BuildContext context, List<VocabEntry> all) {
    final next = all.map((e) => e.due).reduce((a, b) => a.isBefore(b) ? a : b);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              _reviewed == 0
                  ? 'Nothing is due.'
                  : 'Done: $_reviewed cards reviewed.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('Next card: ${_when(next)}'),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => setState(() {
                _queue = _due(all, everything: true);
                _shown = false;
              }),
              child: const Text('Practice all words anyway'),
            ),
          ],
        ),
      ),
    );
  }

  String _when(DateTime due) {
    final days = due.difference(DateTime.now()).inDays;
    if (days <= 0) return 'later today';
    return days == 1 ? 'tomorrow' : 'in $days days';
  }

  Widget _card(BuildContext context, VocabEntry entry, int left) {
    final theme = Theme.of(context);
    final speaker = ref.read(russianSpeakerProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$left left', style: theme.textTheme.labelMedium),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  Text(
                    entry.display,
                    style: theme.textTheme.displaySmall,
                    textAlign: TextAlign.center,
                  ),
                  if (speaker.available)
                    IconButton(
                      tooltip: 'Hear it',
                      icon: const Icon(Icons.volume_up),
                      onPressed: () => speaker.speak(entry.display),
                    ),
                  const SizedBox(height: 16),
                  if (_shown) ...[
                    Text(
                      entry.note.isEmpty ? '(no note)' : entry.note,
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    for (final c in entry.contexts)
                      Card(
                        child: ListTile(
                          title: Text(c.text),
                          subtitle: Text(_bookTitle(c.bookId)),
                          trailing: _bookExists(c.bookId)
                              ? const Icon(Icons.menu_book_outlined)
                              : null,
                          onTap: _bookExists(c.bookId)
                              ? () => _openContext(c)
                              : null,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          if (!_shown)
            FilledButton(
              onPressed: () => setState(() => _shown = true),
              child: const Text('Show answer'),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _answer(entry.key, remembered: false),
                    child: const Text('Again'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _answer(entry.key, remembered: true),
                    child: const Text('Got it'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  bool _bookExists(String id) =>
      ref.read(booksProvider).value?.any((b) => b.id == id) ?? false;

  String _bookTitle(String id) =>
      ref
          .read(booksProvider)
          .value
          ?.where((b) => b.id == id)
          .firstOrNull
          ?.title ??
      'Book no longer in the library';
}
