import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';

/// Plays parts of a local audiobook file.
abstract class SegmentPlayer {
  /// Position in the audio, updated while playing.
  Stream<int> get positionMs;

  /// Latest known position.
  int get currentMs;

  bool get isPlaying;

  /// Plays `[startMs, endMs)` of the audio at [path].
  Future<void> playSegment(String path, int startMs, int endMs);

  Future<void> pause();

  Future<void> dispose();
}

/// Android / iOS implementation on top of just_audio (ExoPlayer / AVPlayer).
class JustAudioSegmentPlayer implements SegmentPlayer {
  final _player = AudioPlayer();
  String? _loaded;
  StreamSubscription<Duration>? _endWatch;

  @override
  Stream<int> get positionMs => _player.positionStream.map((d) => d.inMilliseconds);

  @override
  int get currentMs => _player.position.inMilliseconds;

  @override
  bool get isPlaying => _player.playing;

  @override
  Future<void> playSegment(String path, int startMs, int endMs) async {
    await _endWatch?.cancel();
    if (_loaded != path) {
      await _player.setFilePath(path);
      _loaded = path;
    }
    await _player.seek(Duration(milliseconds: startMs));
    _endWatch = _player.positionStream.listen((p) {
      if (p.inMilliseconds >= endMs) {
        _player.pause();
        _endWatch?.cancel();
      }
    });
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> dispose() async {
    await _endWatch?.cancel();
    await _player.dispose();
  }
}

/// Desktop development fallback: drives the `cvlc` binary.
class VlcSegmentPlayer implements SegmentPlayer {
  Process? _process;
  final _controller = StreamController<int>.broadcast();
  final _clock = Stopwatch();
  Timer? _ticker;
  int _base = 0;

  @override
  Stream<int> get positionMs => _controller.stream;

  @override
  int get currentMs => _base + (_clock.isRunning ? _clock.elapsedMilliseconds : 0);

  @override
  bool get isPlaying => _clock.isRunning;

  @override
  Future<void> playSegment(String path, int startMs, int endMs) async {
    await pause();
    _base = startMs;
    _clock
      ..reset()
      ..start();
    final process = await Process.start('cvlc', [
      '--intf', 'dummy', '--no-video', '--play-and-exit', '--quiet',
      '--start-time=${startMs / 1000}',
      '--stop-time=${endMs / 1000}',
      path,
    ]);
    _process = process;
    unawaited(process.exitCode.then((_) {
      if (_process == process) {
        _clock.stop();
        _base = endMs;
        _ticker?.cancel();
      }
    }));
    _ticker = Timer.periodic(
        const Duration(milliseconds: 250), (_) => _controller.add(currentMs));
  }

  @override
  Future<void> pause() async {
    _base = currentMs;
    _clock
      ..stop()
      ..reset();
    _process?.kill();
    _process = null;
    _ticker?.cancel();
  }

  @override
  Future<void> dispose() async {
    await pause();
    await _controller.close();
  }
}

SegmentPlayer createSegmentPlayer() =>
    Platform.isAndroid || Platform.isIOS ? JustAudioSegmentPlayer() : VlcSegmentPlayer();
