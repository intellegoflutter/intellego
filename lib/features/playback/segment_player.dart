import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Plays parts of one audiobook.
abstract class SegmentPlayer {
  /// Position in the audio, updated while playing.
  Stream<int> get positionMs;

  /// Latest known position.
  int get currentMs;

  bool get isPlaying;

  /// Plays `[startMs, endMs)` of [videoId]'s audio; resolves when started.
  Future<void> playSegment(String videoId, int startMs, int endMs);

  /// Continues from the current position without an end.
  Future<void> resume();

  Future<void> pause();

  Future<void> dispose();
}

/// Direct audio URL of a YouTube video. Prefers a low-bitrate AAC/mp4 stream
/// (speech needs little, and mp4 streams accept range requests for seeking;
/// the opus/webm ones are rejected by googlevideo).
Future<Uri> resolveAudioUrl(String videoId) async {
  final yt = YoutubeExplode();
  try {
    final manifest = await yt.videos.streamsClient.getManifest(videoId);
    final mp4 = manifest.audioOnly.where((s) => s.container.name == 'mp4').toList()
      ..sort((a, b) => a.bitrate.compareTo(b.bitrate));
    final usable = mp4.where((s) => s.bitrate.kiloBitsPerSecond >= 48).toList();
    final pick = usable.isNotEmpty
        ? usable.first
        : (mp4.isNotEmpty ? mp4.last : manifest.audioOnly.withHighestBitrate());
    return pick.url;
  } finally {
    yt.close();
  }
}

/// Android / iOS implementation on top of just_audio (ExoPlayer / AVPlayer).
class JustAudioSegmentPlayer implements SegmentPlayer {
  final _player = AudioPlayer();
  String? _loadedVideo;
  Timer? _stopTimer;
  StreamSubscription<Duration>? _endWatch;

  @override
  Stream<int> get positionMs => _player.positionStream.map((d) => d.inMilliseconds);

  @override
  int get currentMs => _player.position.inMilliseconds;

  @override
  bool get isPlaying => _player.playing;

  Future<void> _load(String videoId, {bool force = false}) async {
    if (!force && _loadedVideo == videoId) return;
    await _player.setAudioSource(AudioSource.uri(await resolveAudioUrl(videoId)));
    _loadedVideo = videoId;
  }

  @override
  Future<void> playSegment(String videoId, int startMs, int endMs) async {
    await _endWatch?.cancel();
    try {
      await _load(videoId);
      await _player.seek(Duration(milliseconds: startMs));
    } catch (_) {
      // Stream URLs expire after a few hours: resolve a fresh one once.
      await _load(videoId, force: true);
      await _player.seek(Duration(milliseconds: startMs));
    }
    _endWatch = _player.positionStream.listen((p) {
      if (p.inMilliseconds >= endMs) {
        _player.pause();
        _endWatch?.cancel();
      }
    });
    unawaited(_player.play());
  }

  @override
  Future<void> resume() async {
    await _endWatch?.cancel();
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> dispose() async {
    _stopTimer?.cancel();
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
  Uri? _url;
  String? _videoId;

  @override
  Stream<int> get positionMs => _controller.stream;

  @override
  int get currentMs => _base + (_clock.isRunning ? _clock.elapsedMilliseconds : 0);

  @override
  bool get isPlaying => _clock.isRunning;

  Future<void> _start(String videoId, int startMs, int? endMs) async {
    await pause();
    if (_videoId != videoId || _url == null) {
      _url = await resolveAudioUrl(videoId);
      _videoId = videoId;
    }
    _base = startMs;
    _clock
      ..reset()
      ..start();
    _process = await Process.start('cvlc', [
      '--intf', 'dummy', '--no-video', '--play-and-exit', '--quiet',
      '--start-time=${startMs / 1000}',
      if (endMs != null) '--stop-time=${endMs / 1000}',
      _url.toString(),
    ]);
    // ignore: unawaited_futures
    _process!.exitCode.then((_) {
      _clock.stop();
      _base = endMs ?? currentMs;
      _ticker?.cancel();
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _controller.add(currentMs));
  }

  @override
  Future<void> playSegment(String videoId, int startMs, int endMs) =>
      _start(videoId, startMs, endMs);

  @override
  Future<void> resume() async {
    if (_videoId != null) await _start(_videoId!, currentMs, null);
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
