import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Records the user's voice into a 16 kHz mono WAV file.
abstract class SpeechRecorder {
  /// Asks for the microphone permission when needed.
  Future<bool> ensurePermission();

  Future<void> start();

  /// Stops and returns the recording, null when nothing was captured.
  Future<File?> stop();

  /// Level 0..1 while recording, for a small meter.
  Stream<double> get level;

  Future<void> dispose();
}

/// Wraps raw 16-bit little-endian mono [pcm] samples in a WAV header.
Uint8List pcm16ToWav(Uint8List pcm, {int sampleRate = 16000}) {
  final out = ByteData(44 + pcm.length);
  void text(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      out.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  out.setUint32(4, 36 + pcm.length, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  out.setUint32(16, 16, Endian.little); // fmt chunk size
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, 1, Endian.little); // mono
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  out.setUint16(32, 2, Endian.little); // block align
  out.setUint16(34, 16, Endian.little); // bits per sample
  text(36, 'data');
  out.setUint32(40, pcm.length, Endian.little);
  final bytes = out.buffer.asUint8List();
  bytes.setRange(44, 44 + pcm.length, pcm);
  return bytes;
}

/// Records through the `record` package as a PCM stream and writes the WAV
/// file itself, so Linux needs no ffmpeg (the package would use it for files).
class RecordPackageRecorder implements SpeechRecorder {
  RecordPackageRecorder({this._root});

  static const _sampleRate = 16000;

  final AudioRecorder _recorder = AudioRecorder();
  Directory? _root;
  StreamSubscription<Uint8List>? _sub;
  final _pcm = BytesBuilder(copy: false);

  Future<Directory> get _dir async {
    final d = _root ??= Directory(
      '${(await getApplicationSupportDirectory()).path}/recordings',
    );
    await d.create(recursive: true);
    return d;
  }

  @override
  Future<bool> ensurePermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    _pcm.clear();
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
      ),
    );
    _sub = stream.listen(_pcm.add);
  }

  @override
  Future<File?> stop() async {
    await _recorder.stop();
    await _sub?.cancel();
    _sub = null;
    final pcm = _pcm.takeBytes();
    if (pcm.length < _sampleRate) return null; // under half a second
    final file = File(
      '${(await _dir).path}/take-${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    await file.writeAsBytes(pcm16ToWav(pcm, sampleRate: _sampleRate));
    return file;
  }

  @override
  Stream<double> get level => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 100))
      // dBFS: -45 is quiet room noise, 0 is full scale.
      .map((a) => ((a.current + 45) / 45).clamp(0.0, 1.0));

  @override
  Future<void> dispose() => _recorder.dispose();
}
