import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import 'vocab.dart';
import 'word_lookup.dart';
import 'word_tokens.dart';

/// Opens the lookup sheet for [word], met in sentence [sentence] of [bookId].
Future<void> showWordSheet(
  BuildContext context, {
  required String word,
  required String bookId,
  required int sentence,
  required String sentenceText,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => WordSheet(
    word: word,
    context: VocabContext(
      bookId: bookId,
      sentence: sentence,
      text: sentenceText,
    ),
  ),
);

class WordSheet extends ConsumerStatefulWidget {
  const WordSheet({super.key, required this.word, required this.context});

  /// The word as written in the text (with its stress mark).
  final String word;
  final VocabContext context;

  @override
  ConsumerState<WordSheet> createState() => _WordSheetState();
}

class _WordSheetState extends ConsumerState<WordSheet> {
  late final String _key = lookupForm(widget.word);
  late final TextEditingController _note;
  late final Future<List<DictEntry>> _wiktionary;
  late final Future<WikiSummary?> _wikipedia;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(vocabProvider.notifier).find(_key);
    _note = TextEditingController(text: saved?.note ?? '');
    final lookup = ref.read(wordLookupProvider);
    _wiktionary = lookup.wiktionary(_key);
    _wikipedia = lookup.wikipedia(_key);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await ref
        .read(vocabProvider.notifier)
        .save(
          key: _key,
          display: widget.word,
          note: _note.text.trim(),
          context: widget.context,
        );
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text('"$_key" saved for practice.')),
    );
  }

  Future<void> _remove() async {
    final navigator = Navigator.of(context);
    await ref.read(vocabProvider.notifier).remove(_key);
    navigator.pop();
  }

  void _useAsNote(String definition) {
    final now = _note.text.trim();
    _note.text = now.isEmpty ? definition : '$now; $definition';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saved = ref.watch(vocabProvider).value?.any((e) => e.key == _key);
    final speaker = ref.read(russianSpeakerProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.word,
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                if (speaker.available)
                  IconButton(
                    tooltip: 'Hear it',
                    icon: const Icon(Icons.volume_up),
                    onPressed: () => speaker.speak(widget.word),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'My note (the back of the card)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _section(theme, 'Wiktionary'),
            FutureBuilder<List<DictEntry>>(
              future: _wiktionary,
              builder: (_, snap) {
                if (snap.hasError) return _error(snap.error);
                if (!snap.hasData) return _loading();
                final entries = snap.data!;
                if (entries.isEmpty) {
                  return const Text('No Russian entry for this form.');
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in entries) ...[
                      Text(
                        e.partOfSpeech,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      for (var k = 0; k < e.definitions.length; k++)
                        InkWell(
                          onTap: () => _useAsNote(e.definitions[k]),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text('${k + 1}. ${e.definitions[k]}'),
                          ),
                        ),
                    ],
                    Text(
                      'Tap a definition to add it to your note.',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _section(theme, 'Wikipedia'),
            FutureBuilder<WikiSummary?>(
              future: _wikipedia,
              builder: (_, snap) {
                if (snap.hasError) return _error(snap.error);
                if (!snap.hasData &&
                    snap.connectionState != ConnectionState.done) {
                  return _loading();
                }
                final w = snap.data;
                if (w == null) return const Text('No article with this name.');
                return InkWell(
                  onTap: () =>
                      launchUrl(w.url, mode: LaunchMode.externalApplication),
                  child: Text(
                    '${w.title}: ${w.extract}',
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _section(theme, 'Open in the browser'),
            Wrap(
              spacing: 8,
              children: [
                for (final (name, url) in lookupLinks(_key))
                  ActionChip(
                    label: Text(name),
                    onPressed: () =>
                        launchUrl(url, mode: LaunchMode.externalApplication),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (saved == true)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove'),
                    onPressed: _remove,
                  ),
                const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.school_outlined),
                  label: Text(saved == true ? 'Save' : 'Add to practice'),
                  onPressed: _save,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(ThemeData theme, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(title, style: theme.textTheme.titleSmall),
  );

  Widget _loading() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );

  Widget _error(Object? e) =>
      Text('$e', style: TextStyle(color: Theme.of(context).colorScheme.error));
}
