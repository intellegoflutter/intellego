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
import '../features/playback/segment_player.dart';
import '../features/speaking/asr_model_store.dart';
import '../features/speaking/feedback_writer.dart';
import '../features/speaking/recorder.dart';
import '../features/speaking/speaking_log.dart';
import '../features/speaking/speech_recognizer.dart';
import '../features/translate/sentence_translator.dart';
import '../features/youtube/youtube_captions.dart';

final bookRepositoryProvider = FutureProvider<BookRepository>((ref) async {
  final docs = await getApplicationDocumentsDirectory();
  return BookRepository(Directory('${docs.path}/books'));
});

/// Dictionary-only accentuator, loaded lazily on first use.
final accentuatorProvider = FutureProvider<Accentuator>(
    (ref) async => loadDictionaryAccentuator());

final modelStoreProvider = Provider<ModelStore>((ref) => ModelStore());

const defaultOmographSize = OmographModelSize.tiny2;

/// Neural accentuator; the models must have been installed via [ModelStore].
final onnxAccentuatorProvider = FutureProvider<Accentuator>((ref) async {
  final store = ref.read(modelStoreProvider);
  return loadOnnxAccentuator(await store.nnDir,
      data: await loadAccentData(), omographSize: defaultOmographSize);
});

final importServiceProvider =
    Provider<ImportService>((ref) => ImportService(fetcher: WebTextFetcher()));

final captionSourceProvider = Provider<CaptionSource>((ref) => YoutubeCaptionSource());

final audioLinkerProvider = Provider<AudioLinker>((ref) => const AudioLinker());

final audioStoreProvider = Provider<AudioStore>((ref) => AudioStore());

final audioDownloaderProvider =
    Provider<YtDlpDownloader>((ref) => YtDlpDownloader(ref.read(audioStoreProvider)));

/// Local audio file of a video, null until downloaded or picked.
final audioFileProvider = FutureProvider.family<File?, String>(
    (ref, videoId) => ref.read(audioStoreProvider).find(videoId));

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

final asrModelStoreProvider = Provider<AsrModelStore>((ref) => AsrModelStore());

final speechRecorderProvider = Provider<SpeechRecorder>((ref) {
  final recorder = RecordPackageRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
});

/// Speech recognizer; the model must have been installed via [AsrModelStore].
final speechRecognizerProvider = FutureProvider<SpeechRecognizer>((ref) async {
  final recognizer = GigaAmRecognizer(await ref.read(asrModelStoreProvider).dir);
  ref.onDispose(recognizer.dispose);
  return recognizer;
});

final feedbackWriterProvider =
    Provider<FeedbackWriter>((ref) => const LocalFeedbackWriter());

/// Reading-aloud results of [bookId], loaded from their file.
final speakingLogProvider = FutureProvider.family<SpeakingLog, String>((ref, bookId) async {
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
    await (await ref.read(bookRepositoryProvider.future)).save(book);
    state = AsyncData([book, ...?state.value]);
  }

  Future<void> updateBook(Book book) async {
    await (await ref.read(bookRepositoryProvider.future)).save(book);
    state = AsyncData([
      for (final b in state.value ?? const <Book>[]) b.id == book.id ? book : b
    ]);
  }

  Future<void> remove(String id) async {
    await (await ref.read(bookRepositoryProvider.future)).delete(id);
    state = AsyncData(
        [for (final b in state.value ?? const <Book>[]) if (b.id != id) b]);
  }
}

final booksProvider =
    AsyncNotifierProvider<BooksNotifier, List<Book>>(BooksNotifier.new);
