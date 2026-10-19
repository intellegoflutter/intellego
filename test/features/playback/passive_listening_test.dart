import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intellego/data/book.dart';
import 'package:intellego/features/playback/passive_listening.dart';
import 'package:intellego/features/playback/segment_player.dart';
import 'package:intellego/features/youtube/caption_models.dart';

TimedText t(int i, int base) =>
    TimedText(text: 'x$i', startMs: base, endMs: base + 1000);

/// Four Russian sentences; two audio files. File a holds track sentences
/// 0..3 (0-4 s), file b holds 4..5 (0-2 s).
Book book({List<int?>? from}) => Book(
  id: 'b',
  title: 'Book',
  createdAt: DateTime.utc(2024),
  sentences: [
    for (var i = 0; i < 4; i++)
      BookSentence(text: 's$i', accented: 's$i', paragraph: 0),
  ],
  tracks: [
    AudioTrack(
      language: 'uk',
      label: 'Ukrainian',
      parts: const [
        AudioPart(videoId: 'a', title: '', from: 0),
        AudioPart(videoId: 'b', title: '', from: 4),
      ],
      sentences: [
        t(0, 0),
        t(1, 1000),
        t(2, 2000),
        t(3, 3000),
        t(4, 0),
        t(5, 1000),
      ],
      alignment: TrackAlignment(
        from: from ?? [0, 1, 3, 4],
        to: [1, 3, 4, 6],
        confidence: [1, 1, 1, 1],
      ),
    ),
  ],
);

class FakePlayer implements SegmentPlayer {
  final positions = StreamController<int>.broadcast();
  final done = StreamController<void>.broadcast();
  final calls = <String>[];
  var playing = false;
  var ms = 0;

  @override
  Stream<int> get positionMs => positions.stream;
  @override
  Stream<void> get completed => done.stream;
  @override
  int get currentMs => ms;
  @override
  bool get isPlaying => playing;
  @override
  Future<void> playSegment(String p, int s, int e, {String? title}) async {}
  @override
  Future<void> playFrom(String path, int startMs, {String? title}) async {
    calls.add('from $path $startMs');
    playing = true;
  }

  @override
  Future<void> resume() async {
    calls.add('resume');
    playing = true;
  }

  @override
  Future<void> seek(int m) async => ms = m;
  @override
  Future<void> pause() async {
    calls.add('pause');
    playing = false;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  group('Book.sentenceAt', () {
    final b = book();
    test('maps audio time back to the Russian sentence', () {
      expect(b.sentenceAt(0, 0, 500), 0);
      expect(b.sentenceAt(0, 0, 1500), 1);
      expect(b.sentenceAt(0, 0, 2500), 1);
      expect(b.sentenceAt(0, 0, 3500), 2);
      expect(b.sentenceAt(0, 1, 500), 3);
      expect(b.sentenceAt(0, 1, 1500), 3);
    });

    test('unaligned sentences keep the previous one current', () {
      final gap = book(from: [0, null, 3, 4]);
      expect(gap.sentenceAt(0, 0, 1500), 0);
    });

    test('unknown track or part', () {
      expect(b.sentenceAt(3, 0, 0), isNull);
      expect(b.sentenceAt(0, 5, 0), isNull);
    });
  });

  group('PassiveListener', () {
    late FakePlayer player;
    late PassiveListener listener;
    late List<PassiveState> states;
    late List<int> saved;
    var missing = <String>{};

    setUp(() {
      player = FakePlayer();
      states = [];
      saved = [];
      missing = {};
      listener = PassiveListener(
        player: player,
        fileFor: (id) async => missing.contains(id) ? null : File('/audio/$id'),
        bookById: (_) => book(),
        onState: states.add,
        onSentence: (_, i) => saved.add(i),
      );
    });

    test('starts at the sentence and follows the audio', () async {
      await listener.start(book(), 0, 1);
      expect(player.calls.single, 'from /audio/a 1000');
      expect(listener.state.sentence, 1);
      expect(listener.state.playing, isTrue);

      player.positions.add(3200);
      await Future<void>.delayed(Duration.zero);
      expect(listener.state.sentence, 2);
      expect(saved, [2]);
    });

    test('moves on to the next part when a file ends', () async {
      await listener.start(book(), 0, 2);
      player.done.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(player.calls.last, 'from /audio/b 0');
      expect(listener.state.part, 1);
      expect(listener.state.sentence, 3);
    });

    test('stops with a message when the next part is missing', () async {
      await listener.start(book(), 0, 2);
      missing = {'b'};
      player.done.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(listener.state.active, isFalse);
      expect(listener.state.message, contains('Part 2'));
    });

    test('stops at the end of the last part', () async {
      await listener.start(book(), 0, 3);
      player.done.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(listener.state.active, isFalse);
      expect(listener.state.message, contains('end'));
    });

    test('pause, resume, skip and stop', () async {
      await listener.start(book(), 0, 1);
      await listener.togglePlay();
      expect(listener.state.playing, isFalse);
      await listener.togglePlay();
      expect(listener.state.playing, isTrue);

      await listener.skip(1);
      expect(listener.state.sentence, 2);
      expect(player.calls.last, 'from /audio/a 3000');
      await listener.skip(1);
      expect(listener.state.part, 1);
      expect(player.calls.last, 'from /audio/b 0');
      await listener.skip(-1);
      expect(listener.state.sentence, 2);

      await listener.stop();
      expect(listener.state.active, isFalse);
      expect(player.playing, isFalse);
    });

    test('starting without audio from there says so', () async {
      final gap = book(from: [0, 1, 3, null]);
      await listener.start(gap, 0, 3);
      expect(listener.state.active, isFalse);
      expect(listener.state.message, isNotNull);
    });

    test('a missing file stops with a message', () async {
      missing = {'a'};
      await listener.start(book(), 0, 0);
      expect(listener.state.active, isFalse);
      expect(listener.state.message, contains('audio file'));
    });
  });
}
