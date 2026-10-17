import 'dart:io';

import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../../data/book.dart';
import 'language_codes.dart';

/// Translates Russian sentences into another language.
abstract class SentenceTranslator {
  /// False where no translator exists (the desktop build).
  bool get supported;

  /// Whether the model for [code] is already on the device.
  Future<bool> isReady(String code);

  /// Translates [text] from Russian into the language [code]. Downloads the
  /// language model first when needed.
  Future<String> translate(String text, String code);

  Future<void> dispose();
}

class NoTranslator implements SentenceTranslator {
  const NoTranslator();

  @override
  bool get supported => false;

  @override
  Future<bool> isReady(String code) async => false;

  @override
  Future<String> translate(String text, String code) =>
      Future.error(UnsupportedError('Translation is only available on Android.'));

  @override
  Future<void> dispose() async {}
}

/// Google ML Kit on-device translation: free, offline once the (about 30 MB)
/// model of each language has been downloaded.
class MlKitTranslator implements SentenceTranslator {
  final _manager = OnDeviceTranslatorModelManager();
  final _translators = <String, OnDeviceTranslator>{};
  var _russianReady = false;

  @override
  bool get supported => true;

  TranslateLanguage _language(String code) =>
      BCP47Code.fromRawValue(code) ??
      (throw ArgumentError('Language "$code" cannot be translated on the device.'));

  @override
  Future<bool> isReady(String code) async =>
      await _manager.isModelDownloaded(TranslateLanguage.russian.bcpCode) &&
      await _manager.isModelDownloaded(_language(code).bcpCode);

  @override
  Future<String> translate(String text, String code) async {
    final target = _language(code);
    if (!_russianReady) {
      await _manager.downloadModel(TranslateLanguage.russian.bcpCode, isWifiRequired: false);
      _russianReady = true;
    }
    if (!await _manager.isModelDownloaded(target.bcpCode)) {
      await _manager.downloadModel(target.bcpCode, isWifiRequired: false);
    }
    final translator = _translators[code] ??= OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.russian, targetLanguage: target);
    return (await translator.translateText(text)).trim();
  }

  @override
  Future<void> dispose() async {
    for (final t in _translators.values) {
      await t.close();
    }
    _translators.clear();
  }
}

SentenceTranslator createSentenceTranslator() =>
    Platform.isAndroid || Platform.isIOS ? MlKitTranslator() : const NoTranslator();

/// Translations that sentence [i] of [book] still lacks: language label ->
/// translated text, for languages with a known code (only [only] if given).
Future<Map<String, String>> missingTranslations(
    Book book, int i, SentenceTranslator translator,
    {String? only}) async {
  final out = <String, String>{};
  for (final t in book.translations) {
    if (only != null && t.name != only) continue;
    if (i >= t.lines.length || t.lines[i].isNotEmpty) continue;
    final code = languageCodeFor(t.name);
    if (code == null) continue;
    final text = await translator.translate(book.sentences[i].text, code);
    if (text.isNotEmpty) out[t.name] = text;
  }
  return out;
}

/// [book] with the [lines] (language label -> text) written into sentence [i];
/// lines that were filled in the meantime are kept.
Book withTranslatedLines(Book book, int i, Map<String, String> lines) {
  if (lines.isEmpty) return book;
  return book.withTranslations([
    for (final t in book.translations)
      if (lines.containsKey(t.name) && i < t.lines.length && t.lines[i].isEmpty)
        t.withLine(i, lines[t.name]!)
      else
        t
  ]);
}
