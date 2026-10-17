import 'dart:async';
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';

/// Reads Russian text aloud with a synthetic voice (the audiobook is
/// Ukrainian, so this is how a sentence is heard in Russian).
abstract class RussianSpeaker {
  /// False where no voice can be used at all.
  bool get available;

  /// Speaks [text] and completes when it has been spoken or [stop] was called.
  Future<void> speak(String text);

  Future<void> stop();

  Future<void> dispose();
}

class NoSpeaker implements RussianSpeaker {
  const NoSpeaker();

  @override
  bool get available => false;

  @override
  Future<void> speak(String text) =>
      Future.error(UnsupportedError('No Russian voice is available here.'));

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
  bool? _ready;

  @override
  bool get available => true;

  Future<void> _prepare() async {
    if (_ready == true) return;
    final languages = (await _tts.getLanguages as List?)?.map((e) => '$e').toList() ?? const [];
    final hasRussian = languages.any((l) => l.toLowerCase().startsWith('ru'));
    if (!hasRussian) {
      throw StateError('No Russian voice is installed. Open the phone settings → '
          'System → Languages → Text-to-speech and install Russian voice data.');
    }
    await _tts.setLanguage('ru-RU');
    await _tts.setSpeechRate(rate);
    await _tts.awaitSpeakCompletion(true);
    _ready = true;
  }

  @override
  Future<void> speak(String text) async {
    await _prepare();
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    if (_ready == true) await _tts.stop();
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
  Future<void> speak(String text) async {
    await stop();
    try {
      final process = _process = await Process.start('spd-say', ['-l', 'ru', '-r', '-30', '-w', text]);
      await process.exitCode;
    } on ProcessException {
      throw StateError('Install speech-dispatcher (spd-say) to hear Russian on this computer.');
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
