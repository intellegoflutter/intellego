import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'ctc_decoder.dart';
import 'gigaam_features.dart';
import 'wav_reader.dart';

/// Turns a recording (16-bit WAV) into text.
abstract class SpeechRecognizer {
  Future<String> transcribe(File wav);

  Future<void> dispose();
}

/// The Russian GigaAM-v2 CTC model (int8 ONNX export of sherpa-onnx) on the
/// same ONNX runtime the stress models use. Features are computed in a
/// background isolate; the model itself is loaded on the first recording.
class GigaAmRecognizer implements SpeechRecognizer {
  GigaAmRecognizer(this.modelDir);

  /// Directory holding `model.int8.onnx` and `tokens.txt`.
  final Directory modelDir;

  OrtSession? _session;
  List<String>? _tokens;
  Future<void>? _loading;

  Future<void> _load() => _loading ??= () async {
    try {
      _tokens = parseTokens(
        await File('${modelDir.path}/tokens.txt').readAsString(),
      );
      _session = await OnnxRuntime().createSession(
        '${modelDir.path}/model.int8.onnx',
      );
    } catch (e) {
      _loading = null;
      throw StateError('Could not load the speech model: $e');
    }
  }();

  @override
  Future<String> transcribe(File wav) async {
    await _load();
    final session = _session!;
    final tokens = _tokens!;

    final features = await compute(_featuresOf, wav.path);
    if (features.frames < 4) return '';

    final input = await OrtValue.fromList(features.data, [
      1,
      gigaMels,
      features.frames,
    ]);
    final lengths = await OrtValue.fromList(
      Int64List.fromList([features.frames]),
      [1],
    );
    Map<String, OrtValue>? outputs;
    try {
      outputs = await session.run({
        'features': input,
        'feature_lengths': lengths,
      });
      final out = outputs['log_probs'] ?? outputs.values.first;
      final flat = await out.asFlattenedList();
      final vocab = out.shape.last;
      final frames = out.shape[out.shape.length - 2];
      return ctcGreedyDecode(
        [for (final v in flat) (v as num).toDouble()],
        frames,
        vocab,
        tokens,
      );
    } finally {
      await input.dispose();
      await lengths.dispose();
      for (final o in outputs?.values ?? const <OrtValue>[]) {
        await o.dispose();
      }
    }
  }

  @override
  Future<void> dispose() async {
    await _session?.close();
    _session = null;
    _loading = null;
  }
}

({Float32List data, int frames}) _featuresOf(String path) {
  final pcm = readWavFile(File(path));
  return gigaLogMel(resample(pcm.samples, pcm.sampleRate, gigaSampleRate));
}
