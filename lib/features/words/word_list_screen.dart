import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'vocab.dart';

/// All saved words: edit a note, delete a word.
class WordListScreen extends ConsumerWidget {
  const WordListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = [...?ref.watch(vocabProvider).value]
      ..sort((a, b) => a.key.compareTo(b.key));
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: Text('Words (${words.length})')),
      body: words.isEmpty
          ? const Center(child: Text('No words yet.'))
          : ListView.builder(
              itemCount: words.length,
              itemBuilder: (_, k) {
                final e = words[k];
                return Dismissible(
                  key: ValueKey(e.key),
                  background: Container(color: Colors.red),
                  onDismissed: (_) =>
                      ref.read(vocabProvider.notifier).remove(e.key),
                  child: ListTile(
                    title: Text(e.display),
                    subtitle: Text(e.note.isEmpty ? '—' : e.note),
                    trailing: Text(e.isDue(now) ? 'due' : 'box ${e.box}'),
                    onTap: () => _edit(context, ref, e),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, VocabEntry e) async {
    final controller = TextEditingController(text: e.note);
    final note = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(e.display),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
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
    );
    controller.dispose();
    if (note == null) return;
    final c = e.contexts.first;
    await ref
        .read(vocabProvider.notifier)
        .save(key: e.key, display: e.display, note: note, context: c);
  }
}
