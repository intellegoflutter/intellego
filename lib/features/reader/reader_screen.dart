import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../app/providers.dart';
import '../../data/book.dart';
import '../library/add_pages_dialog.dart';
import '../library/link_audio_screen.dart';
import '../playback/audio_downloader.dart';
import '../speaking/asr_model_store.dart';
import '../translate/language_codes.dart';
import '../translate/sentence_translator.dart';
import '../speaking/pronunciation_comparer.dart';
import '../speaking/recorder.dart';
import '../speaking/speaking_log.dart';
import '../speaking/speaking_sheet.dart';
import '../youtube/caption_models.dart';
import 'reading_position.dart';
import 'translations_dialogs.dart';
import 'ukrainian_text_tools.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> with WidgetsBindingObserver {
  bool _showUkrainian = true;
  int? _playing;
  bool _busy = false;
  double? _downloadProgress;
  int _playingPart = 0;
  int? _recordingIndex;
  int? _lastRecorded;
  bool _transcribing = false;
  final _translating = ValueNotifier<bool>(false);

  final _positions = ItemPositionsListener.create();
  int? _startIndex;
  int _topIndex = 0;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _positions.itemPositions.addListener(_onScrolled);
    ReadingPosition.load(widget.bookId).then((i) {
      if (mounted) setState(() => _startIndex = i);
    });
  }

  void _onScrolled() {
    _topIndex = topVisibleIndex(
        [for (final p in _positions.itemPositions.value) (p.index, p.itemTrailingEdge)]);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600),
        () => ReadingPosition.save(widget.bookId, _topIndex));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Save at once when the app goes to the background: it may be killed there.
    if (state != AppLifecycleState.resumed && _startIndex != null) {
      _saveTimer?.cancel();
      ReadingPosition.save(widget.bookId, _topIndex);
    }
  }

  Future<void> _play(Book book, int i) async {
    final seg = book.audioSegmentFor(i);
    if (seg == null) return;
    final file = await ref.read(audioFileProvider(seg.videoId).future);
    if (file == null) {
      _toast('Add the audio file first (banner at the top).');
      return;
    }
    setState(() {
      _playing = i;
      _playingPart = seg.part;
    });
    try {
      await ref.read(segmentPlayerProvider).playSegment(file.path, seg.startMs, seg.endMs);
    } catch (e) {
      _toast('Playback failed: $e');
    }
  }

  // --- reading aloud ---------------------------------------------------

  Future<void> _record(Book book, int i) async {
    if (_transcribing) return;
    final recorder = ref.read(speechRecorderProvider);
    if (_recordingIndex == i) {
      await _finishRecording(book, i);
      return;
    }
    if (_recordingIndex != null) return;
    final store = ref.read(asrModelStoreProvider);
    if (!await store.isInstalled()) {
      if (!await _downloadSpeechModel(store)) return;
    }
    if (!await recorder.ensurePermission()) {
      _toast('Allow the microphone for Intellego to read aloud.');
      return;
    }
    try {
      await ref.read(segmentPlayerProvider).pause();
      await recorder.start();
      if (mounted) setState(() => _recordingIndex = i);
    } catch (e) {
      _toast('Could not start recording: $e');
    }
  }

  Future<void> _finishRecording(Book book, int i) async {
    final recorder = ref.read(speechRecorderProvider);
    setState(() {
      _lastRecorded = _recordingIndex;
      _recordingIndex = null;
      _transcribing = true;
    });
    try {
      final file = await recorder.stop();
      if (file == null) {
        _toast('Nothing was recorded.');
        return;
      }
      final recognizer = await ref.read(speechRecognizerProvider.future);
      final heard = await recognizer.transcribe(file);
      final sentence = book.sentences[i];
      final comparison = compareWords(accented: sentence.accented, heard: heard);
      final feedback = await ref
          .read(feedbackWriterProvider)
          .write(accented: sentence.accented, comparison: comparison);
      final log = await ref.read(speakingLogProvider(book.id).future);
      await log.record(i, comparison.score);
      if (!mounted) return;
      setState(() => _transcribing = false);
      unawaited(_fillTranslations(book.id, i));
      await _showResult(book.id, i, file, heard, comparison, feedback);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _transcribing = false);
    }
  }

  Future<void> _showResult(String bookId, int i, File recording, String heard,
      Comparison comparison, String feedback) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Consumer(builder: (context, ref, _) {
        final practiced = ref
                .watch(booksProvider)
                .value
                ?.where((b) => b.id == bookId)
                .firstOrNull
                ?.sentences[i]
                .practiced ??
            false;
        final live = ref.watch(booksProvider).value?.where((b) => b.id == bookId).firstOrNull;
        final lines = [
          for (final t in live?.translations ?? const <Translation>[])
            if (t.visible && i < t.lines.length && t.lines[i].isNotEmpty) (t.name, t.lines[i])
        ];
        return ValueListenableBuilder<bool>(
          valueListenable: _translating,
          builder: (context, busy, _) => SpeakingSheet(
          comparison: comparison,
          heard: heard,
          feedback: feedback,
          practiced: practiced,
          translations: lines,
          translating: busy,
          onAddLanguages: (live?.translations.isEmpty ?? false) &&
                  ref.read(sentenceTranslatorProvider).supported
              ? () => _addDefaultLanguages(bookId, i)
              : null,
          onPlayRecording: () => ref
              .read(segmentPlayerProvider)
              .playSegment(recording.path, 0, 3600000),
          onRetry: () => Navigator.pop(sheetContext, 'retry'),
          onMarkPracticed: () {
            final book =
                ref.read(booksProvider).value?.where((b) => b.id == bookId).firstOrNull;
            if (book != null) _toggle(book, i);
          },
        ));
      }),
    );
    await ref.read(segmentPlayerProvider).pause();
    if (action == 'retry' && mounted) {
      final book = ref.read(booksProvider).value?.where((b) => b.id == bookId).firstOrNull;
      if (book != null) await _record(book, i);
    }
  }

  /// Asks before the one-time model download and shows its progress.
  Future<bool> _downloadSpeechModel(AsrModelStore store) async {
    final mb = (AsrModelStore.totalBytes / 1e6).round();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Speech recognition model'),
        content: Text('To check your reading Intellego needs a Russian speech '
            'model of about $mb MB. It is downloaded once and then works '
            'offline. Use Wi-Fi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Download')),
        ],
      ),
    );
    if (ok != true || !mounted) return false;
    final progress = ValueNotifier<double>(0);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Downloading speech model…'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (context, v, _) => Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: v),
            const SizedBox(height: 8),
            Text('${(v * mb).round()} of $mb MB'),
          ]),
        ),
      ),
    ));
    var installed = false;
    try {
      await store.install(onProgress: (p) => progress.value = p);
      installed = true;
    } catch (e) {
      _toast('Download failed: $e');
    } finally {
      if (mounted) Navigator.of(context).pop();
      progress.dispose();
    }
    return installed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positions.itemPositions.removeListener(_onScrolled);
    _saveTimer?.cancel();
    _translating.dispose();
    if (_startIndex != null) ReadingPosition.save(widget.bookId, _topIndex);
    if (_recordingIndex != null) unawaited(_recorder?.stop());
    super.dispose();
  }

  SpeechRecorder? get _recorder {
    try {
      return ref.read(speechRecorderProvider);
    } catch (_) {
      return null;
    }
  }

  // --- translations ------------------------------------------------------

  Book? _latest(String bookId) =>
      ref.read(booksProvider).value?.where((b) => b.id == bookId).firstOrNull;

  /// Translates the empty lines of sentence [i] with the phone's offline
  /// translator ([only]: just that language) and saves them in the book.
  Future<void> _fillTranslations(String bookId, int i, {String? only, bool announce = false}) async {
    final translator = ref.read(sentenceTranslatorProvider);
    final book = _latest(bookId);
    if (book == null) return;
    if (!translator.supported) {
      if (announce) _toast('Offline translation is available on the phone only.');
      return;
    }
    if (book.translations.isEmpty) {
      if (announce) _toast('Add a language first (menu ⋮ → Languages).');
      return;
    }
    _translating.value = true;
    try {
      for (final t in book.translations) {
        final code = languageCodeFor(t.name);
        if ((only == null || only == t.name) && code != null && !await translator.isReady(code)) {
          _toast('Downloading the ${t.name} translation model (about 30 MB, once)…');
          break;
        }
      }
      final lines = await missingTranslations(book, i, translator, only: only);
      if (lines.isEmpty && announce) {
        _toast('Nothing to translate: the languages have no known code or are filled.');
      }
      final fresh = _latest(bookId);
      if (fresh != null) {
        await ref.read(booksProvider.notifier).updateBook(withTranslatedLines(fresh, i, lines));
      }
    } catch (e) {
      _toast('Translation failed: $e');
    } finally {
      _translating.value = false;
    }
  }

  /// A tap on an empty language line: translate it, or edit when that is
  /// not possible.
  Future<void> _fillOrEdit(Book book, int i, String language) async {
    final canTranslate =
        ref.read(sentenceTranslatorProvider).supported && languageCodeFor(language) != null;
    if (canTranslate) {
      await _fillTranslations(book.id, i, only: language, announce: true);
    } else {
      await editSentenceTranslations(context, ref, book.id, i);
    }
  }

  Future<void> _addDefaultLanguages(String bookId, int i) async {
    final book = _latest(bookId);
    if (book == null) return;
    final have = {for (final t in book.translations) t.name.toLowerCase()};
    await ref.read(booksProvider.notifier).updateBook(book.withTranslations([
          ...book.translations,
          for (final (name, _) in suggestedLanguages.take(2))
            if (!have.contains(name.toLowerCase()))
              Translation(name: name, lines: List.filled(book.sentences.length, '')),
        ]));
    await _fillTranslations(bookId, i);
  }

  Future<void> _downloadAudio(String id) async {
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

  Future<void> _pickAudio(String id) async {
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
    final uk = audio.indexAt(ref.read(segmentPlayerProvider).currentMs, part: _playingPart);
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
                case 'part':
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => LinkAudioScreen(bookId: book.id, addPart: true)));
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
              if (hasAudio)
                const PopupMenuItem(value: 'part', child: Text('Add next audio part…')),
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
    final audio = book.audio!;
    final missing = <int>[];
    for (var k = 0; k < audio.parts.length; k++) {
      final file = ref.watch(audioFileProvider(audio.parts[k].videoId));
      if (!file.isLoading && file.value == null) missing.add(k);
    }
    if (missing.isEmpty) return const SizedBox.shrink();
    final downloading = _downloadProgress != null;
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final k in missing) ...[
            Text(audio.parts.length == 1
                ? 'The audio is not on this device yet. Playing sentences '
                    'needs the audiobook file.'
                : 'Part ${k + 1} of the audio is not on this device yet'
                    '${audio.parts[k].title.isEmpty ? '' : ': ${audio.parts[k].title}'}.'),
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
                    onPressed: () => _downloadAudio(audio.parts[k].videoId),
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Choose audio file…'),
                  onPressed: () => _pickAudio(audio.parts[k].videoId),
                ),
              ]),
            if (k != missing.last) const SizedBox(height: 12),
          ],
        ]),
      ),
    );
  }

  Widget _list(Book book) {
    final attempts = ref.watch(speakingLogProvider(book.id)).value;
    final start = _startIndex;
    if (start == null) return const SizedBox.shrink();
    return ScrollablePositionedList.separated(
        itemPositionsListener: _positions,
        initialScrollIndex: start.clamp(0, book.sentences.isEmpty ? 0 : book.sentences.length - 1),
        itemCount: book.sentences.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) => _SentenceTile(
          index: i,
          book: book,
          showUkrainian: _showUkrainian,
          playing: _playing == i,
          recording: _recordingIndex == i,
          transcribing: _transcribing && _recordingIndex == null && _lastRecorded == i,
          best: attempts?.attempts[i],
          onRecord: () => _record(book, i),
          onPlay: () => _play(book, i),
          onToggle: () => _toggle(book, i),
          onEdit: () => _editUkrainian(book, i),
          onSync: () => _syncHere(book, i),
          onTranslate: () => editSentenceTranslations(context, ref, book.id, i),
          onFillLanguage: (name) => _fillOrEdit(book, i, name),
          onTranslateAll: () => _fillTranslations(book.id, i, announce: true),
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
    required this.recording,
    required this.transcribing,
    required this.best,
    required this.onRecord,
    required this.onPlay,
    required this.onToggle,
    required this.onEdit,
    required this.onSync,
    required this.onTranslate,
    required this.onFillLanguage,
    required this.onTranslateAll,
  });

  final int index;
  final Book book;
  final bool showUkrainian;
  final bool playing, recording, transcribing;
  final SpeakingAttempt? best;
  final VoidCallback onRecord, onPlay, onToggle, onEdit, onSync, onTranslate, onTranslateAll;
  final void Function(String language) onFillLanguage;

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
                    if (best != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                            'Read aloud ${best!.attempts}×, best ${(best!.best * 100).round()}%',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: theme.colorScheme.outline)),
                      ),
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
                                  onTap: () => onFillLanguage(t.name),
                                  onLongPress: onTranslate,
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
              if (transcribing)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                IconButton(
                  tooltip: recording ? 'Stop and check' : 'Read aloud',
                  icon: Icon(recording ? Icons.stop_circle : Icons.mic_none,
                      color: recording ? theme.colorScheme.error : null),
                  onPressed: onRecord,
                ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'sync') onSync();
                  if (v == 'translate') onTranslate();
                  if (v == 'translateAll') onTranslateAll();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'translate', child: Text('Edit languages…')),
                  if (book.translations.isNotEmpty)
                    const PopupMenuItem(
                        value: 'translateAll', child: Text('Translate with the phone (offline)')),
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
