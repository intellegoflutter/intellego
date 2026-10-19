import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

/// Plays parts of a local audiobook file.
abstract class SegmentPlayer {
  /// Position in the audio, updated while playing.
  Stream<int> get positionMs;

  /// Fires when continuous playback ([playFrom]) reaches the end of the file.
  Stream<void> get completed;

  /// Latest known position.
  int get currentMs;

  bool get isPlaying;

  /// Plays `[startMs, endMs)` of the audio at [path]. [title] is shown in the
  /// media notification where there is one.
  Future<void> playSegment(
    String path,
    int startMs,
    int endMs, {
    String? title,
  });

  /// Plays the audio at [path] from [startMs] to the end of the file.
  Future<void> playFrom(String path, int startMs, {String? title});

  /// Continues after [pause].
  Future<void> resume();

  /// Moves to [ms] in the current file, playing or not.
  Future<void> seek(int ms);

  Future<void> pause();

  Future<void> dispose();
}

/// Android / iOS implementation on top of just_audio (ExoPlayer / AVPlayer).
class JustAudioSegmentPlayer implements SegmentPlayer {
  final _player = AudioPlayer();
  String? _loaded;
  StreamSubscription<Duration>? _endWatch;

  Future<void> _load(String path, String? title) async {
    final key = '$path|$title';
    if (_loaded == key) return;
    await _player.setAudioSource(
      AudioSource.file(
        path,
        // just_audio_background shows this in the notification and requires
        // a tag on every source.
        tag: MediaItem(
          id: path,
          title: title ?? path.split(Platform.pathSeparator).last,
        ),
      ),
    );
    _loaded = key;
  }

  @override
  Stream<void> get completed => _player.processingStateStream
      // The stream starts with the current state, which is not news.
      .skip(1)
      .where((s) => s == ProcessingState.completed);

  @override
  Stream<int> get positionMs =>
      _player.positionStream.map((d) => d.inMilliseconds);

  @override
  int get currentMs => _player.position.inMilliseconds;

  @override
  bool get isPlaying => _player.playing;

  @override
  Future<void> playSegment(
    String path,
    int startMs,
    int endMs, {
    String? title,
  }) async {
    await _endWatch?.cancel();
    await _load(path, title);
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
  Future<void> playFrom(String path, int startMs, {String? title}) async {
    await _endWatch?.cancel();
    _endWatch = null;
    await _load(path, title);
    await _player.seek(Duration(milliseconds: startMs));
    unawaited(_player.play());
  }

  @override
  Future<void> resume() async {
    unawaited(_player.play());
  }

  @override
  Future<void> seek(int ms) => _player.seek(Duration(milliseconds: ms));

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
  final _completed = StreamController<void>.broadcast();
  final _clock = Stopwatch();
  Timer? _ticker;
  int _base = 0;
  String? _path;
  bool _continuous = false;

  @override
  Stream<void> get completed => _completed.stream;

  @override
  Stream<int> get positionMs => _controller.stream;

  @override
  int get currentMs =>
      _base + (_clock.isRunning ? _clock.elapsedMilliseconds : 0);

  @override
  bool get isPlaying => _clock.isRunning;

  @override
  Future<void> playSegment(
    String path,
    int startMs,
    int endMs, {
    String? title,
  }) => _start(path, startMs, endMs);

  @override
  Future<void> playFrom(String path, int startMs, {String? title}) =>
      _start(path, startMs, null);

  @override
  Future<void> resume() async {
    final path = _path;
    if (path != null && !isPlaying) await _start(path, _base, null);
  }

  @override
  Future<void> seek(int ms) async {
    final path = _path;
    if (path != null && isPlaying) {
      await _start(path, ms, null);
    } else {
      _base = ms;
      _controller.add(ms);
    }
  }

  Future<void> _start(String path, int startMs, int? endMs) async {
    await pause();
    _path = path;
    _continuous = endMs == null;
    _base = startMs;
    _clock
      ..reset()
      ..start();
    final process = await Process.start('cvlc', [
      '--intf',
      'dummy',
      '--no-video',
      '--play-and-exit',
      '--quiet',
      '--start-time=${startMs / 1000}',
      if (endMs != null) '--stop-time=${endMs / 1000}',
      path,
    ]);
    _process = process;
    unawaited(
      process.exitCode.then((_) {
        if (_process == process) {
          _clock.stop();
          _ticker?.cancel();
          if (endMs != null) _base = endMs;
          if (_continuous) _completed.add(null);
        }
      }),
    );
    _ticker = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _controller.add(currentMs),
    );
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
    await _completed.close();
  }
}

SegmentPlayer createSegmentPlayer() => Platform.isAndroid || Platform.isIOS
    ? JustAudioSegmentPlayer()
    : VlcSegmentPlayer();
