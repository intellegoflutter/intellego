import 'dart:async';
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';

import '../translate/language_codes.dart';

/// Reads text aloud with a synthetic voice: Russian by default (the audiobook
/// is Ukrainian, so this is how a sentence is heard in Russian), or the
/// language of a translation.
abstract class RussianSpeaker {
  /// False where no voice can be used at all.
  bool get available;

  /// Speaks [text] in [language] (a code such as `ru` or `it`) and completes
  /// when it has been spoken or [stop] was called.
  Future<void> speak(String text, {String language = 'ru'});

  Future<void> stop();

  Future<void> dispose();
}

class NoSpeaker implements RussianSpeaker {
  const NoSpeaker();

  @override
  bool get available => false;

  @override
  Future<void> speak(String text, {String language = 'ru'}) =>
      Future.error(UnsupportedError('No voice is available here.'));

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// The phone's own text-to-speech engine (Google TTS on most Android phones),
/// slowed down a little for a learner.
class PlatformSpeaker implements RussianSpeaker {
  PlatformSpeaker({this.rate = 0.42});

  final double rate;
  final _tts = FlutterTts();
  String? _language;
  bool _configured = false;

  @override
  bool get available => true;

  Future<void> _prepare(String language) async {
    if (_language == language) return;
    final languages =
        (await _tts.getLanguages as List?)?.map((e) => '$e').toList() ??
        const [];
    final matches = languages.where(
      (l) => l.toLowerCase().split(RegExp(r'[-_]')).first == language,
    );
    if (matches.isEmpty) {
      throw StateError(
        'No ${languageLabelFor(language)} voice is installed. Open the phone '
        'settings → System → Languages → Text-to-speech and install '
        '${languageLabelFor(language)} voice data.',
      );
    }
    await _tts.setLanguage(matches.first);
    if (!_configured) {
      await _tts.setSpeechRate(rate);
      await _tts.awaitSpeakCompletion(true);
      _configured = true;
    }
    _language = language;
  }

  @override
  Future<void> speak(String text, {String language = 'ru'}) async {
    await _prepare(language);
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    if (_configured) await _tts.stop();
  }

  @override
  Future<void> dispose() => stop();
}

/// Linux: speech-dispatcher (`spd-say`) with its Russian voice, when installed.
class SpdSaySpeaker implements RussianSpeaker {
  Process? _process;

  @override
  bool get available => true;

  @override
  Future<void> speak(String text, {String language = 'ru'}) async {
    await stop();
    try {
      final process = _process = await Process.start('spd-say', [
        '-l',
        language,
        '-r',
        '-30',
        '-w',
        text,
      ]);
      await process.exitCode;
    } on ProcessException {
      throw StateError(
        'Install speech-dispatcher (spd-say) to hear speech on this computer.',
      );
    } finally {
      _process = null;
    }
  }

  @override
  Future<void> stop() async {
    _process?.kill();
    _process = null;
    try {
      await Process.run('spd-say', ['-S']);
    } on ProcessException {
      // not installed: nothing to stop
    }
  }

  @override
  Future<void> dispose() => stop();
}

RussianSpeaker createRussianSpeaker() {
  if (Platform.isAndroid || Platform.isIOS) return PlatformSpeaker();
  if (Platform.isLinux) return SpdSaySpeaker();
  return const NoSpeaker();
}
