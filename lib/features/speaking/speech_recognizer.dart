import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Turns a recording (16-bit mono WAV) into text.
abstract class SpeechRecognizer {
  Future<String> transcribe(File wav);

  Future<void> dispose();
}

/// Russian GigaAM CTC model run by sherpa-onnx in a worker isolate, so that
/// loading the model and decoding never block the UI. The model is loaded
/// once, on the first recording.
class SherpaRecognizer implements SpeechRecognizer {
  SherpaRecognizer(this.modelDir);

  /// Directory holding `model.int8.onnx` and `tokens.txt`.
  final Directory modelDir;

  Isolate? _isolate;
  SendPort? _send;
  ReceivePort? _receive;
  Completer<void>? _starting;
  var _nextId = 0;
  final _pending = <int, Completer<String>>{};

  Future<void> _start() async {
    if (_send != null) return;
    if (_starting != null) return _starting!.future;
    final starting = _starting = Completer<void>();
    try {
      final receive = _receive = ReceivePort();
      final ready = Completer<SendPort>();
      receive.listen((message) {
        if (message is SendPort) {
          ready.complete(message);
        } else if (message is List && message.length == 3) {
          final done = _pending.remove(message[0] as int);
          if (message[2] != null) {
            done?.completeError(StateError(message[2] as String));
          } else {
            done?.complete(message[1] as String);
          }
        }
      });
      _isolate = await Isolate.spawn(_worker, [receive.sendPort, modelDir.path]);
      _send = await ready.future;
      starting.complete();
    } catch (e) {
      starting.completeError(e);
      _starting = null;
      rethrow;
    }
  }

  @override
  Future<String> transcribe(File wav) async {
    await _start();
    final id = _nextId++;
    final done = _pending[id] = Completer<String>();
    _send!.send([id, wav.path]);
    return done.future;
  }

  @override
  Future<void> dispose() async {
    _isolate?.kill(priority: Isolate.immediate);
    _receive?.close();
    _isolate = null;
    _send = null;
    for (final p in _pending.values) {
      p.completeError(StateError('Recognizer closed'));
    }
    _pending.clear();
  }
}

void _worker(List<Object> init) {
  final main = init[0] as SendPort;
  final dir = init[1] as String;
  final port = ReceivePort();
  sherpa.initBindings();
  late final sherpa.OfflineRecognizer recognizer;
  String? loadError;
  try {
    recognizer = sherpa.OfflineRecognizer(sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        nemoCtc: sherpa.OfflineNemoEncDecCtcModelConfig(model: '$dir/model.int8.onnx'),
        tokens: '$dir/tokens.txt',
        numThreads: 2,
      ),
    ));
  } catch (e) {
    loadError = 'Could not load the speech model: $e';
  }
  main.send(port.sendPort);
  port.listen((message) {
    final request = message as List;
    final id = request[0] as int;
    if (loadError != null) {
      main.send([id, '', loadError]);
      return;
    }
    try {
      final wave = sherpa.readWave(request[1] as String);
      final stream = recognizer.createStream();
      stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
      recognizer.decode(stream);
      final text = recognizer.getResult(stream).text;
      stream.free();
      main.send([id, text.trim(), null]);
    } catch (e) {
      main.send([id, '', 'Recognition failed: $e']);
    }
  });
}
