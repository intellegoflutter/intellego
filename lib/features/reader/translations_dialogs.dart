import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/book.dart';
import '../translate/language_codes.dart';
import '../translate/sentence_translator.dart';
import 'ukrainian_text_tools.dart';

Book? _find(WidgetRef ref, String id) =>
    ref.read(booksProvider).value?.where((b) => b.id == id).firstOrNull;

/// Add, rename, hide, bulk-fill and delete the extra languages of a book.
class LanguagesDialog extends ConsumerStatefulWidget {
  const LanguagesDialog({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<LanguagesDialog> createState() => _LanguagesDialogState();
}

class _LanguagesDialogState extends ConsumerState<LanguagesDialog> {
  final _newName = TextEditingController();

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  Future<void> _save(List<Translation> next) async {
    final book = _find(ref, widget.bookId);
    if (book == null) return;
    await ref
        .read(booksProvider.notifier)
        .updateBook(book.withTranslations(next));
  }

  void _say(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _add(Book book) async {
    final name = _newName.text.trim();
    if (name.isEmpty) return;
    if (book.translations.any(
      (t) => t.name.toLowerCase() == name.toLowerCase(),
    )) {
      _say('"$name" already exists.');
      return;
    }
    _newName.clear();
    await _save([
      ...book.translations,
      Translation(name: name, lines: List.filled(book.sentences.length, '')),
    ]);
  }

  Future<String?> _ask(
    String title,
    String initial, {
    int lines = 1,
    String? help,
  }) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 500,
          child: TextField(
            controller: c,
            autofocus: true,
            maxLines: lines == 1 ? 1 : lines,
            decoration: InputDecoration(
              helperText: help,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('OK'),
          ),
        ],
      ),
    ).whenComplete(c.dispose);
  }

  Future<void> _paste(Book book, int index) async {
    final t = book.translations[index];
    final text = await _ask(
      'Paste ${t.name} lines',
      '',
      lines: 12,
      help:
          'One line per Russian sentence: ${book.sentences.length} lines, '
          'same order as copied. A blank line keeps the current text.',
    );
    if (text == null || text.trim().isEmpty) return;
    final lines = importUkrainian(text);
    if (lines.length != book.sentences.length) {
      _say('Expected ${book.sentences.length} lines but got ${lines.length}.');
      return;
    }
    final merged = [
      for (var i = 0; i < lines.length; i++)
        lines[i].isEmpty ? t.lines[i] : lines[i],
    ];
    await _save([...book.translations]..[index] = t.copyWith(lines: merged));
    _say(
      '${t.name}: ${merged.where((l) => l.isNotEmpty).length} sentences filled.',
    );
  }

  /// Translates every empty line of [t] with the phone's offline translator,
  /// showing progress and a way to stop; what was done so far is kept.
  Future<void> _translateAll(Book book, Translation t) async {
    final translator = ref.read(sentenceTranslatorProvider);
    if (!translator.supported) {
      _say('Offline translation is available on the phone only.');
      return;
    }
    final code = languageCodeFor(t.name);
    if (code == null) {
      _say(
        '"${t.name}" is not a language the phone knows; rename it (e.g. Italian).',
      );
      return;
    }
    final missing = t.lines.where((l) => l.isEmpty).length;
    if (missing == 0) {
      _say('${t.name} is already complete.');
      return;
    }
    final progress = ValueNotifier<int>(0);
    var cancelled = false;
    final navigator = Navigator.of(context);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('Translating to ${t.name}'),
          content: ValueListenableBuilder<int>(
            valueListenable: progress,
            builder: (context, done, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: done == 0 ? null : done / missing,
                ),
                const SizedBox(height: 12),
                Text(
                  done == 0
                      ? 'Starting (the first time the ${t.name} model, about '
                            '30 MB, is downloaded)…'
                      : '$done of $missing sentences',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => cancelled = true,
              child: const Text('Stop'),
            ),
          ],
        ),
      ),
    );
    String? failure;
    var added = 0;
    try {
      added = await translateLanguage(
        bookId: book.id,
        name: t.name,
        translator: translator,
        latest: () => _find(ref, book.id),
        save: (b) => ref.read(booksProvider.notifier).updateBook(b),
        onProgress: (done, _) => progress.value = done,
        cancelled: () => cancelled,
      );
    } catch (e) {
      failure = '$e';
    }
    progress.dispose();
    navigator.pop();
    if (!mounted) return;
    _say(
      failure != null
          ? '${t.name}: translation stopped ($failure).'
          : cancelled
          ? '${t.name}: stopped after $added sentences.'
          : '${t.name}: $added sentences translated.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final book = ref
        .watch(booksProvider)
        .value
        ?.where((b) => b.id == widget.bookId)
        .firstOrNull;
    if (book == null) return const SizedBox.shrink();
    return AlertDialog(
      title: const Text('Languages'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add languages to compare while you read. Fill them sentence '
                'by sentence from the ⋮ menu of a sentence, or paste a whole '
                'translation at once.',
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copy Russian text (one sentence per line)'),
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text: exportUkrainian(book.sentences.map((s) => s.text)),
                    ),
                  );
                  _say('${book.sentences.length} sentences copied.');
                },
              ),
              const Divider(height: 24),
              for (var i = 0; i < book.translations.length; i++) _row(book, i),
              Wrap(
                spacing: 8,
                children: [
                  for (final (name, _) in suggestedLanguages)
                    if (!book.translations.any(
                      (t) => t.name.toLowerCase() == name.toLowerCase(),
                    ))
                      ActionChip(
                        label: Text('+ $name'),
                        onPressed: () => _save([
                          ...book.translations,
                          Translation(
                            name: name,
                            lines: List.filled(book.sentences.length, ''),
                          ),
                        ]),
                      ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newName,
                      decoration: const InputDecoration(
                        labelText: 'New language (e.g. English)',
                      ),
                      onSubmitted: (_) => _add(book),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Add',
                    onPressed: () => _add(book),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _row(Book book, int i) {
    final t = book.translations[i];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Switch(
        value: t.visible,
        onChanged: (v) =>
            _save([...book.translations]..[i] = t.copyWith(visible: v)),
      ),
      title: Text(t.name),
      subtitle: Text('${t.filled} of ${book.sentences.length} sentences'),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          switch (v) {
            case 'translate':
              await _translateAll(book, t);
            case 'paste':
              await _paste(book, i);
            case 'rename':
              final name = await _ask('Rename language', t.name);
              if (name != null && name.trim().isNotEmpty) {
                await _save(
                  [...book.translations]..[i] = t.copyWith(name: name.trim()),
                );
              }
            case 'copy':
              await Clipboard.setData(
                ClipboardData(text: exportUkrainian(t.lines)),
              );
              _say('${t.name} copied.');
            case 'delete':
              await _save([...book.translations]..removeAt(i));
          }
        },
        itemBuilder: (_) => [
          if (ref.read(sentenceTranslatorProvider).supported)
            const PopupMenuItem(
              value: 'translate',
              child: Text('Translate all with the phone…'),
            ),
          const PopupMenuItem(value: 'paste', child: Text('Paste lines…')),
          const PopupMenuItem(value: 'copy', child: Text('Copy lines')),
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}

/// Replaces the whole text of [controller] with the clipboard's text.
Future<void> _pasteInto(TextEditingController controller) async {
  final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
  if (text == null || text.isEmpty) return;
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
}

/// Edit every language of one sentence.
Future<void> editSentenceTranslations(
  BuildContext context,
  WidgetRef ref,
  String bookId,
  int index,
) async {
  final book = _find(ref, bookId);
  if (book == null) return;
  if (book.translations.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Add a language first (menu ⋮ → Languages).'),
      ),
    );
    return;
  }
  final controllers = [
    for (final t in book.translations)
      TextEditingController(text: t.lines[index]),
  ];
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Sentence ${index + 1}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book.sentences[index].accented,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              for (var k = 0; k < controllers.length; k++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: controllers[k],
                    autofocus: k == 0,
                    maxLines: null,
                    decoration: InputDecoration(
                      labelText: book.translations[k].name,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.content_paste),
                        tooltip: 'Replace with the clipboard',
                        onPressed: () => _pasteInto(controllers[k]),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (saved == true) {
    final fresh = _find(ref, bookId);
    if (fresh != null) {
      await ref
          .read(booksProvider.notifier)
          .updateBook(
            fresh.withTranslations([
              for (var k = 0; k < fresh.translations.length; k++)
                k < controllers.length
                    ? fresh.translations[k].withLine(index, controllers[k].text)
                    : fresh.translations[k],
            ]),
          );
    }
  }
  for (final c in controllers) {
    c.dispose();
  }
}
