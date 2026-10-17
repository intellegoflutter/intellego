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
import '../features/playback/segment_player.dart';
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

final segmentPlayerProvider = Provider<SegmentPlayer>((ref) {
  final player = createSegmentPlayer();
  ref.onDispose(player.dispose);
  return player;
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
