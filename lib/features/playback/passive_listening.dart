import 'dart:async';
import 'dart:io';

import '../../data/book.dart';
import 'segment_player.dart';

/// What the "listen from here" feature is doing.
class PassiveState {
  const PassiveState({
    this.bookId,
    this.track = 0,
    this.part = 0,
    this.sentence,
    this.playing = false,
    this.message,
  });

  static const idle = PassiveState();

  /// The book being listened to; null when idle.
  final String? bookId;
  final int track, part;

  /// The Russian sentence being spoken.
  final int? sentence;
  final bool playing;

  /// Why playback stopped, when it was not the user's doing.
  final String? message;

  bool get active => bookId != null;

  PassiveState copyWith({
    int? part,
    int? sentence,
    bool? playing,
    String? message,
  }) => PassiveState(
    bookId: bookId,
    track: track,
    part: part ?? this.part,
    sentence: sentence ?? this.sentence,
    playing: playing ?? this.playing,
    message: message,
  );
}

/// Plays a downloaded audiobook continuously from a sentence, moving on to
/// the next audio file by itself, and reports which sentence is being spoken
/// so that the reader can follow.
class PassiveListener {
  PassiveListener({
    required this.player,
    required this.fileFor,
    required this.bookById,
    required this.onState,
    this.onSentence,
  });

  final SegmentPlayer player;

  /// The local file of an audio part, or null when it is not on the device.
  final Future<File?> Function(String videoId) fileFor;
  final Book? Function(String bookId) bookById;
  final void Function(PassiveState state) onState;

  /// Called whenever the spoken sentence changes (to remember the position).
  final void Function(String bookId, int sentence)? onSentence;

  PassiveState state = PassiveState.idle;
  StreamSubscription<int>? _position;
  StreamSubscription<void>? _completed;

  void _set(PassiveState next) {
    state = next;
    onState(next);
  }

  /// Starts at the first sentence at or after [from] that has audio.
  Future<void> start(Book book, int track, int from) async {
    final i = _nextWithAudio(book, track, from, 1, inclusive: true);
    if (i == null) {
      _set(PassiveState(message: 'There is no audio from here.'));
      return;
    }
    await _stopListening();
    _set(PassiveState(bookId: book.id, track: track, sentence: i));
    if (!await _playAt(book, i)) return;
    _position = player.positionMs.listen(_onPosition);
    _completed = player.completed.listen((_) => _onCompleted());
  }

  int? _nextWithAudio(
    Book book,
    int track,
    int from,
    int step, {
    bool inclusive = false,
  }) {
    var i = inclusive ? from : from + step;
    while (i >= 0 && i < book.sentences.length) {
      if (book.hasAudioAt(i, track)) return i;
      i += step;
    }
    return null;
  }

  /// Plays from sentence [i]; false when the audio is not available.
  Future<bool> _playAt(Book book, int i) async {
    final seg = book.audioSegmentFor(i, state.track);
    if (seg == null) return false;
    final file = await fileFor(seg.videoId);
    if (file == null) {
      await stop(message: 'Add the audio file first (banner at the top).');
      return false;
    }
    try {
      await player.playFrom(
        file.path,
        seg.startMs,
        title: '${book.title} · ${book.tracks[state.track].label}',
      );
    } catch (e) {
      await stop(message: 'Playback failed: $e');
      return false;
    }
    _set(state.copyWith(part: seg.part, sentence: i, playing: true));
    return true;
  }

  void _onPosition(int ms) {
    final id = state.bookId;
    if (id == null || !state.playing) return;
    final book = bookById(id);
    if (book == null) return;
    final i = book.sentenceAt(state.track, state.part, ms);
    if (i != null && i != state.sentence) {
      _set(state.copyWith(sentence: i));
      onSentence?.call(id, i);
    }
  }

  Future<void> _onCompleted() async {
    final id = state.bookId;
    final book = id == null ? null : bookById(id);
    if (book == null) return;
    final track = book.tracks[state.track];
    final next = state.part + 1;
    if (next >= track.parts.length) {
      await stop(message: 'Reached the end of the audiobook.');
      return;
    }
    final file = await fileFor(track.parts[next].videoId);
    if (file == null) {
      await stop(message: 'Part ${next + 1} is not on the device.');
      return;
    }
    // The first Russian sentence whose audio is in the next part.
    final first = track.partRange(next).$1;
    int? sentence;
    for (var i = 0; i < book.sentences.length; i++) {
      if (book.hasAudioAt(i, state.track) &&
          book.tracks[state.track].alignment.to[i]! > first) {
        sentence = i;
        break;
      }
    }
    try {
      await player.playFrom(
        file.path,
        0,
        title: '${book.title} · ${track.label}',
      );
    } catch (e) {
      await stop(message: 'Playback failed: $e');
      return;
    }
    _set(state.copyWith(part: next, sentence: sentence, playing: true));
  }

  Future<void> pause() async {
    if (!state.active) return;
    await player.pause();
    _set(state.copyWith(playing: false));
  }

  Future<void> resume() async {
    if (!state.active || state.playing) return;
    await player.resume();
    _set(state.copyWith(playing: true));
  }

  Future<void> togglePlay() => state.playing ? pause() : resume();

  /// Moves one sentence on ([step] 1) or back (-1).
  Future<void> skip(int step) async {
    final id = state.bookId, current = state.sentence;
    final book = id == null ? null : bookById(id);
    if (book == null || current == null) return;
    final i = _nextWithAudio(book, state.track, current, step);
    if (i == null) return;
    await _playAt(book, i);
    onSentence?.call(book.id, i);
  }

  Future<void> _stopListening() async {
    await _position?.cancel();
    await _completed?.cancel();
    _position = null;
    _completed = null;
  }

  /// Ends listening; [message] says why when it was not the user's choice.
  Future<void> stop({String? message}) async {
    await _stopListening();
    if (state.active) await player.pause();
    _set(PassiveState(message: message));
  }
}
