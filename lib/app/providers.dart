import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/book.dart';
import '../data/book_repository.dart';
import '../features/alignment/audio_linker.dart';
import '../features/import/import_service.dart';
import '../features/import/web_text_fetcher.dart';
import '../features/nlp/accent/accent_dictionary_loader.dart';
import '../features/nlp/accent/accentuator.dart';
import '../features/nlp/accent/onnx/model_store.dart';
import '../features/nlp/accent/onnx/onnx_accentuator_loader.dart';
import '../features/playback/audio_downloader.dart';
import '../features/playback/audio_store.dart';
import '../features/playback/passive_listening.dart';
import '../features/playback/segment_player.dart';
import '../features/reader/reading_position.dart';
import '../features/speaking/asr_model_store.dart';
import '../features/speaking/feedback_writer.dart';
import '../features/speaking/recorder.dart';
import '../features/speaking/russian_speaker.dart';
import '../features/speaking/speaking_log.dart';
import '../features/speaking/speech_recognizer.dart';
import '../features/translate/sentence_translator.dart';
import '../features/words/vocab.dart';
import '../features/words/word_lookup.dart';
import '../features/youtube/youtube_captions.dart';

final bookRepositoryProvider = FutureProvider<BookRepository>((ref) async {
  final docs = await getApplicationDocumentsDirectory();
  return BookRepository(Directory('${docs.path}/books'));
});

/// Dictionary-only accentuator, loaded lazily on first use.
final accentuatorProvider = FutureProvider<Accentuator>(
  (ref) async => loadDictionaryAccentuator(),
);

final modelStoreProvider = Provider<ModelStore>((ref) => ModelStore());

const defaultOmographSize = OmographModelSize.tiny2;

/// Neural accentuator; the models must have been installed via [ModelStore].
final onnxAccentuatorProvider = FutureProvider<Accentuator>((ref) async {
  final store = ref.read(modelStoreProvider);
  return loadOnnxAccentuator(
    await store.nnDir,
    data: await loadAccentData(),
    omographSize: defaultOmographSize,
  );
});

final importServiceProvider = Provider<ImportService>(
  (ref) => ImportService(fetcher: WebTextFetcher()),
);

final captionSourceProvider = Provider<CaptionSource>(
  (ref) => YoutubeCaptionSource(),
);

final audioLinkerProvider = Provider<AudioLinker>(
  (ref) => AudioLinker(translator: ref.read(sentenceTranslatorProvider)),
);

final audioStoreProvider = Provider<AudioStore>((ref) => AudioStore());

final audioDownloaderProvider = Provider<YtDlpDownloader>(
  (ref) => YtDlpDownloader(ref.read(audioStoreProvider)),
);

/// Local audio file of a video, null until downloaded or picked.
final audioFileProvider = FutureProvider.family<File?, String>(
  (ref, videoId) => ref.read(audioStoreProvider).find(videoId),
);

final segmentPlayerProvider = Provider<SegmentPlayer>((ref) {
  final player = createSegmentPlayer();
  ref.onDispose(player.dispose);
  return player;
});

final sentenceTranslatorProvider = Provider<SentenceTranslator>((ref) {
  final translator = createSentenceTranslator();
  ref.onDispose(translator.dispose);
  return translator;
});

final russianSpeakerProvider = Provider<RussianSpeaker>((ref) {
  final speaker = createRussianSpeaker();
  ref.onDispose(speaker.dispose);
  return speaker;
});

final asrModelStoreProvider = Provider<AsrModelStore>((ref) => AsrModelStore());

final speechRecorderProvider = Provider<SpeechRecorder>((ref) {
  final recorder = RecordPackageRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
});

/// Speech recognizer; the model must have been installed via [AsrModelStore].
final speechRecognizerProvider = FutureProvider<SpeechRecognizer>((ref) async {
  final recognizer = GigaAmRecognizer(
    await ref.read(asrModelStoreProvider).dir,
  );
  ref.onDispose(recognizer.dispose);
  return recognizer;
});

final feedbackWriterProvider = Provider<FeedbackWriter>(
  (ref) => const LocalFeedbackWriter(),
);

/// Reading-aloud results of [bookId], loaded from their file.
final speakingLogProvider = FutureProvider.family<SpeakingLog, String>((
  ref,
  bookId,
) async {
  final docs = await getApplicationDocumentsDirectory();
  final log = SpeakingLog(File('${docs.path}/speaking/$bookId.json'));
  await log.load();
  return log;
});

class BooksNotifier extends AsyncNotifier<List<Book>> {
  @override
  Future<List<Book>> build() async =>
      (await ref.watch(bookRepositoryProvider.future)).loadAll();

  Future<void> add(Book book) async {
    final saved = await (await ref.read(bookRepositoryProvider.future))
        .save(book);
    state = AsyncData([saved, ...?state.value]);
  }

  Future<void> updateBook(Book book) async {
    final saved = await (await ref.read(bookRepositoryProvider.future))
        .save(book);
    state = AsyncData([
      for (final b in state.value ?? const <Book>[])
        b.id == saved.id ? saved : b,
    ]);
  }

  Future<void> remove(String id) async {
    await (await ref.read(bookRepositoryProvider.future)).delete(id);
    state = AsyncData([
      for (final b in state.value ?? const <Book>[])
        if (b.id != id) b,
    ]);
  }
}

final booksProvider = AsyncNotifierProvider<BooksNotifier, List<Book>>(
  BooksNotifier.new,
);

/// "Listen from here": continuous audiobook playback that the reader follows.
class PassiveListeningNotifier extends Notifier<PassiveState> {
  late final PassiveListener _listener;

  @override
  PassiveState build() {
    _listener = PassiveListener(
      player: ref.read(segmentPlayerProvider),
      fileFor: (id) => ref.read(audioFileProvider(id).future),
      bookById: (id) =>
          ref.read(booksProvider).value?.where((b) => b.id == id).firstOrNull,
      onState: (s) => state = s,
      onSentence: ReadingPosition.save,
    );
    ref.onDispose(_listener.dispose);
    return PassiveState.idle;
  }

  Future<void> start(Book book, int track, int from) async {
    await ref.read(russianSpeakerProvider).stop();
    await _listener.start(book, track, from);
  }

  Future<void> togglePlay() => _listener.togglePlay();

  Future<void> skip(int step) => _listener.skip(step);

  Future<void> stop() => _listener.stop();
}

final passiveListeningProvider =
    NotifierProvider<PassiveListeningNotifier, PassiveState>(
      PassiveListeningNotifier.new,
    );

final wordLookupProvider = Provider<WordLookupService>((ref) {
  final service = WordLookupService();
  ref.onDispose(service.close);
  return service;
});

/// The words saved for practice.
class VocabNotifier extends AsyncNotifier<List<VocabEntry>> {
  Future<VocabFile> _file() async {
    final docs = await getApplicationDocumentsDirectory();
    return VocabFile(File('${docs.path}/vocab.json'));
  }

  @override
  Future<List<VocabEntry>> build() async => (await _file()).load();

  Future<void> _set(List<VocabEntry> next) async {
    state = AsyncData(next);
    await (await _file()).save(next);
  }

  VocabEntry? find(String key) =>
      state.value?.where((e) => e.key == key).firstOrNull;

  /// Saves [key]; a word already saved keeps its schedule and gains
  /// [context] and the new [note].
  Future<void> save({
    required String key,
    required String display,
    required String note,
    required VocabContext context,
  }) async {
    final all = state.value ?? const <VocabEntry>[];
    final now = DateTime.now();
    final old = find(key);
    final entry = old == null
        ? VocabEntry(
            key: key,
            display: display,
            note: note,
            contexts: [context],
            added: now,
            due: now,
          )
        : withContext(old, context).copyWith(note: note);
    await _set([
      for (final e in all)
        if (e.key != key) e,
      entry,
    ]);
  }

  Future<void> remove(String key) async => _set([
    for (final e in state.value ?? const <VocabEntry>[])
      if (e.key != key) e,
  ]);

  Future<void> review(String key, {required bool remembered}) async {
    final all = state.value ?? const <VocabEntry>[];
    final now = DateTime.now();
    await _set([
      for (final e in all)
        e.key == key ? scheduleNext(e, remembered: remembered, now: now) : e,
    ]);
  }
}

final vocabProvider = AsyncNotifierProvider<VocabNotifier, List<VocabEntry>>(
  VocabNotifier.new,
);
