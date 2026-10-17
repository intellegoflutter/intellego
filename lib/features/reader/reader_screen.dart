import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/book.dart';
import '../library/add_pages_dialog.dart';
import '../library/link_audio_screen.dart';
import '../playback/audio_downloader.dart';
import '../youtube/caption_models.dart';
import 'translations_dialogs.dart';
import 'ukrainian_text_tools.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  bool _showUkrainian = true;
  int? _playing;
  bool _busy = false;
  double? _downloadProgress;

  Future<void> _play(Book book, int i) async {
    final range = book.audioRangeFor(i);
    if (range == null) return;
    final file = await ref.read(audioFileProvider(book.audio!.videoId).future);
    if (file == null) {
      _toast('Add the audio file first (banner at the top).');
      return;
    }
    setState(() => _playing = i);
    try {
      await ref.read(segmentPlayerProvider).playSegment(file.path, range.$1, range.$2);
    } catch (e) {
      _toast('Playback failed: $e');
    }
  }

  Future<void> _downloadAudio(Book book) async {
    final id = book.audio!.videoId;
    setState(() => _downloadProgress = 0);
    try {
      await ref.read(audioDownloaderProvider).download(id,
          onProgress: (p) => setState(() => _downloadProgress = p));
      ref.invalidate(audioFileProvider(id));
      _toast('Audio downloaded.');
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _downloadProgress = null);
    }
  }

  Future<void> _pickAudio(Book book) async {
    final id = book.audio!.videoId;
    final picked = await FilePicker.pickFiles(type: FileType.audio);
    final path = picked.isEmpty ? null : picked.first.path;
    if (path == null) return;
    setState(() => _downloadProgress = 0);
    try {
      await ref.read(audioStoreProvider).importFile(id, File(path));
      ref.invalidate(audioFileProvider(id));
      _toast('Audio added.');
    } catch (e) {
      _toast('Could not add the file: $e');
    } finally {
      if (mounted) setState(() => _downloadProgress = null);
    }
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  /// Declares that sentence [i] is spoken where the audio is right now.
  Future<void> _syncHere(Book book, int i) async {
    final audio = book.audio;
    if (audio == null) return;
    final uk = audio.indexAt(ref.read(segmentPlayerProvider).currentMs);
    if (uk == null) {
      _toast('Play the audio first, then choose "Sync here".');
      return;
    }
    final anchors = [
      for (final a in audio.anchors)
        if (a.$1 != i) a,
      (i, uk),
    ];
    await _realign(book, anchors);
  }

  Future<void> _realign(Book book, List<(int, int)> anchors) async {
    setState(() => _busy = true);
    try {
      final relinked = await ref.read(audioLinkerProvider).relink(book, anchors: anchors);
      await ref.read(booksProvider.notifier).updateBook(relinked);
    } catch (e) {
      _toast('Alignment failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editUkrainian(Book book, int i) async {
    final s = book.sentences[i];
    final audio = book.audio;
    if (audio == null || !s.hasAudio) return;
    final controllers = [
      for (var q = s.ukFrom!; q < s.ukTo!; q++)
        TextEditingController(text: audio.sentences[q].text)
    ];
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Ukrainian'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final c in controllers)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(controller: c, maxLines: null),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      final next = [...audio.sentences];
      for (var k = 0; k < controllers.length; k++) {
        next[s.ukFrom! + k] = next[s.ukFrom! + k].copyWith(text: controllers[k].text.trim());
      }
      await ref.read(booksProvider.notifier).updateBook(book.withAudio(audio.copyWith(sentences: next)));
    }
    for (final c in controllers) {
      c.dispose();
    }
  }

  Future<void> _copyUkrainian(Book book) async {
    await Clipboard.setData(
        ClipboardData(text: exportUkrainian(book.audio!.sentences.map((e) => e.text))));
    _toast('${book.audio!.sentences.length} Ukrainian sentences copied, one per line.');
  }

  Future<void> _pasteUkrainian(Book book) async {
    final audio = book.audio!;
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paste corrected Ukrainian'),
        content: SizedBox(
          width: 500,
          child: TextField(
            controller: controller,
            maxLines: 12,
            decoration: InputDecoration(
              helperText: 'One sentence per line, ${audio.sentences.length} lines '
                  'in the same order as copied.',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Apply')),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty) return;
    final lines = importUkrainian(text);
    if (lines.length != audio.sentences.length) {
      _toast('Expected ${audio.sentences.length} lines but got ${lines.length}. '
          'Keep one sentence per line.');
      return;
    }
    final next = [
      for (var k = 0; k < lines.length; k++)
        TimedText(
            text: lines[k].isEmpty ? audio.sentences[k].text : lines[k],
            startMs: audio.sentences[k].startMs,
            endMs: audio.sentences[k].endMs)
    ];
    final updated = book.withAudio(audio.copyWith(sentences: next));
    await ref.read(booksProvider.notifier).updateBook(updated);
    await _realign(updated, audio.anchors);
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(booksProvider).value?.where((b) => b.id == widget.bookId).firstOrNull;
    if (book == null) return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    final hasAudio = book.audio != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(book.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (!hasAudio)
            IconButton(
              tooltip: 'Link audiobook (YouTube)',
              icon: const Icon(Icons.headphones),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => LinkAudioScreen(bookId: book.id))),
            ),
          if (hasAudio)
            IconButton(
              tooltip: _showUkrainian ? 'Hide Ukrainian' : 'Show Ukrainian',
              icon: Icon(_showUkrainian ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _showUkrainian = !_showUkrainian),
            ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'more':
                  await showDialog<void>(
                      context: context,
                      builder: (_) => AddPagesDialog(bookId: book.id));
                case 'languages':
                  await showDialog<void>(
                      context: context,
                      builder: (_) => LanguagesDialog(bookId: book.id));
                case 'link':
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => LinkAudioScreen(bookId: book.id)));
                case 'copy':
                  await _copyUkrainian(book);
                case 'paste':
                  await _pasteUkrainian(book);
                case 'realign':
                  await _realign(book, book.audio!.anchors);
                case 'clear':
                  await _realign(book, const []);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'languages', child: Text('Languages…')),
              if (canAddPages(book))
                const PopupMenuItem(value: 'more', child: Text('Add more pages…')),
              PopupMenuItem(value: 'link', child: Text(hasAudio ? 'Change audiobook' : 'Link audiobook')),
              if (hasAudio) ...const [
                PopupMenuItem(value: 'copy', child: Text('Copy Ukrainian text')),
                PopupMenuItem(value: 'paste', child: Text('Paste corrected Ukrainian')),
                PopupMenuItem(value: 'realign', child: Text('Re-align')),
                PopupMenuItem(value: 'clear', child: Text('Forget sync points')),
              ],
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: _busy
              ? const LinearProgressIndicator()
              : LinearProgressIndicator(
                  value: book.sentences.isEmpty
                      ? 0
                      : book.practicedCount / book.sentences.length),
        ),
      ),
      body: Column(children: [
        if (hasAudio) _audioBanner(book),
        Expanded(child: _list(book)),
      ]),
    );
  }

  Widget _audioBanner(Book book) {
    final file = ref.watch(audioFileProvider(book.audio!.videoId));
    if (file.isLoading || file.value != null) return const SizedBox.shrink();
    final downloading = _downloadProgress != null;
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('The audio is not on this device yet. Playing sentences '
              'needs the audiobook file.'),
          const SizedBox(height: 8),
          if (downloading)
            LinearProgressIndicator(
                value: _downloadProgress == 0 ? null : _downloadProgress)
          else
            Wrap(spacing: 8, children: [
              if (YtDlpDownloader.supported)
                FilledButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Download from YouTube'),
                  onPressed: () => _downloadAudio(book),
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('Choose audio file…'),
                onPressed: () => _pickAudio(book),
              ),
            ]),
        ]),
      ),
    );
  }

  Widget _list(Book book) {
    return ListView.separated(
        itemCount: book.sentences.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) => _SentenceTile(
          index: i,
          book: book,
          showUkrainian: _showUkrainian,
          playing: _playing == i,
          onPlay: () => _play(book, i),
          onToggle: () => _toggle(book, i),
          onEdit: () => _editUkrainian(book, i),
          onSync: () => _syncHere(book, i),
          onTranslate: () => editSentenceTranslations(context, ref, book.id, i),
        ),
      );
  }

  void _toggle(Book book, int i) {
    final next = [...book.sentences];
    next[i] = next[i].copyWith(practiced: !next[i].practiced);
    ref.read(booksProvider.notifier).updateBook(book.withSentences(next));
  }
}

class _SentenceTile extends StatelessWidget {
  const _SentenceTile({
    required this.index,
    required this.book,
    required this.showUkrainian,
    required this.playing,
    required this.onPlay,
    required this.onToggle,
    required this.onEdit,
    required this.onSync,
    required this.onTranslate,
  });

  final int index;
  final Book book;
  final bool showUkrainian;
  final bool playing;
  final VoidCallback onPlay, onToggle, onEdit, onSync, onTranslate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = book.sentences[index];
    final uk = book.ukrainianFor(index);
    final weak = s.confidence != null && s.confidence! < 0.08;
    return Material(
      color: playing ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4) : null,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 36,
                child: Text('${index + 1}', style: theme.textTheme.labelMedium),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.accented,
                        style: theme.textTheme.titleLarge?.copyWith(height: 1.4)),
                    if (showUkrainian && uk != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(uk,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: weak
                                    ? theme.colorScheme.outline
                                    : theme.colorScheme.secondary,
                                fontStyle: weak ? FontStyle.italic : null)),
                      ),
                    for (final t in book.translations)
                      if (t.visible)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: t.lines[index].isEmpty
                              ? InkWell(
                                  onTap: onTranslate,
                                  child: Text('+ ${t.name}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: theme.colorScheme.outline)),
                                )
                              : InkWell(
                                  onTap: onTranslate,
                                  child: Text.rich(TextSpan(children: [
                                    TextSpan(
                                        text: '${t.name}: ',
                                        style: TextStyle(
                                            color: theme.colorScheme.outline,
                                            fontWeight: FontWeight.w600)),
                                    TextSpan(text: t.lines[index]),
                                  ]), style: theme.textTheme.bodyMedium),
                                ),
                        ),
                  ],
                ),
              ),
              if (s.hasAudio)
                IconButton(
                  tooltip: 'Play',
                  icon: Icon(playing ? Icons.volume_up : Icons.play_circle_outline),
                  onPressed: onPlay,
                ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'sync') onSync();
                  if (v == 'translate') onTranslate();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'translate', child: Text('Edit languages…')),
                  if (book.audio != null && s.hasAudio)
                    const PopupMenuItem(value: 'edit', child: Text('Edit Ukrainian')),
                  if (book.audio != null)
                    const PopupMenuItem(value: 'sync', child: Text('Sync here (audio is at this sentence)')),
                ],
              ),
              Icon(
                s.practiced ? Icons.check_circle : Icons.radio_button_unchecked,
                color: s.practiced ? Colors.green : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
