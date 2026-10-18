import 'package:flutter_test/flutter_test.dart';
import 'package:intellego/data/book.dart';
import 'package:intellego/features/alignment/audio_linker.dart';
import 'package:intellego/features/translate/sentence_translator.dart';
import 'package:intellego/features/reader/ukrainian_text_tools.dart';
import 'package:intellego/features/youtube/caption_models.dart';
import 'package:intellego/features/youtube/cue_sentences.dart';
import 'package:intellego/features/youtube/youtube_captions.dart';

void main() {
  group('cuesToSentences', () {
    test('splits across cues and interpolates times', () {
      final s = cuesToSentences(const [
        Cue(startMs: 0, durationMs: 4000, text: 'Перше речення. Друге'),
        Cue(startMs: 2000, durationMs: 4000, text: 'речення тут.'),
      ]);
      expect(s.map((e) => e.text), ['Перше речення.', 'Друге речення тут.']);
      expect(s[0].startMs, 0);
      expect(s[0].endMs, lessThanOrEqualTo(2000)); // first cue ends when the next starts
      expect(s[1].startMs, greaterThan(0));
      expect(s[1].endMs, 6000);
      expect(s[1].startMs, greaterThanOrEqualTo(s[0].endMs));
    });

    test('cuts long unpunctuated runs at cue boundaries', () {
      final cues = [
        for (var i = 0; i < 30; i++)
          Cue(startMs: i * 3000, durationMs: 3000, text: 'слово ' * 8),
      ];
      final s = cuesToSentences(cues, maxSentenceChars: 120);
      expect(s.length, greaterThan(3));
      expect(s.every((e) => e.text.length <= 160), isTrue);
      for (var i = 1; i < s.length; i++) {
        expect(s[i].startMs, greaterThanOrEqualTo(s[i - 1].startMs));
      }
    });

    test('empty cues', () => expect(cuesToSentences(const []), isEmpty));
  });

  test('ukrainian export / import round trip', () {
    expect(exportUkrainian(['Один\nрядок.', ' Два. ']), 'Один рядок.\nДва.');
    expect(importUkrainian('а\r\n\nб\n\n'), ['а', '', 'б']);
  });

  AudioTrack track({String language = 'uk', String label = 'Ukrainian', TrackAlignment? alignment}) =>
      AudioTrack.single(
        language: language,
        label: label,
        videoId: 'v',
        videoTitle: 'T',
        sentences: const [
          TimedText(text: 'x', startMs: 0, endMs: 100),
          TimedText(text: 'y', startMs: 100, endMs: 250),
        ],
        anchors: const [(0, 0)],
        alignment: alignment ??
            const TrackAlignment(from: [0, null], to: [2, null], confidence: [0.5, null]),
      );

  test('book json keeps the audio tracks and their alignment', () {
    final book = Book(
      id: '1',
      title: 't',
      createdAt: DateTime(2026),
      sentences: const [
        BookSentence(text: 'a', accented: 'a', paragraph: 0),
        BookSentence(text: 'b', accented: 'b', paragraph: 0),
      ],
      tracks: [track()],
    );
    final back = Book.fromJson(book.toJson());
    expect(back.trackTextFor(0), 'x y');
    expect(back.audioRangeFor(0), (0, 250));
    expect(back.audioRangeFor(1), isNull);
    expect(back.hasAudioAt(1), isFalse);
    expect(back.confidenceAt(0), closeTo(0.5, 1e-9));
    expect(back.tracks.single.anchors, [(0, 0)]);
    expect(back.tracks.single.language, 'uk');
    expect(back.tracks.single.indexAt(150), 1);
    expect(back.tracks.single.indexAt(-5), isNull);
  });

  test('books saved before audio tracks keep their Ukrainian audiobook', () {
    final legacy = {
      'id': 'old',
      'title': 'Old',
      'createdAt': '2026-01-01T00:00:00.000',
      'sentences': [
        {'text': 'a', 'accented': 'a', 'paragraph': 0, 'ukFrom': 0, 'ukTo': 2, 'confidence': 0.5},
        {'text': 'b', 'accented': 'b', 'paragraph': 0},
        {'text': 'c', 'accented': 'c', 'paragraph': 1, 'ukFrom': 2, 'ukTo': 3, 'practiced': true},
      ],
      'audio': {
        'videoId': 'v',
        'videoTitle': 'T',
        'sentences': [
          {'text': 'x', 'start': 0, 'end': 100},
          {'text': 'y', 'start': 100, 'end': 250},
          {'text': 'z', 'start': 250, 'end': 300},
        ],
        'anchors': [
          [2, 2]
        ],
      },
    };
    final book = Book.fromJson(legacy);
    expect(book.tracks.single.language, 'uk');
    expect(book.tracks.single.label, 'Ukrainian');
    expect(book.tracks.single.parts.single.videoId, 'v');
    expect(book.trackTextFor(0), 'x y');
    expect(book.trackTextFor(1), isNull);
    expect(book.trackTextFor(2), 'z');
    expect(book.confidenceAt(0), 0.5);
    expect(book.sentences[2].practiced, isTrue);
    expect(book.tracks.single.anchors, [(2, 2)]);
    // Saved again it uses the new format and still reads back the same.
    final saved = book.toJson();
    expect(saved.containsKey('audio'), isFalse);
    expect(saved['sentences'].first.containsKey('ukFrom'), isFalse);
    final again = Book.fromJson(saved);
    expect(again.trackTextFor(2), 'z');
    expect(again.audioRangeFor(0), (0, 250));
  });

  test('alignment that stops early leaves later sentences without audio', () {
    final book = Book(
      id: '1',
      title: 't',
      createdAt: DateTime(2026),
      sentences: const [
        BookSentence(text: 'a', accented: 'a', paragraph: 0),
        BookSentence(text: 'b', accented: 'b', paragraph: 0),
      ],
      tracks: [track()],
    ).appended(const [BookSentence(text: 'c', accented: 'c', paragraph: 1)]);
    expect(book.sentences, hasLength(3));
    expect(book.hasAudioAt(2), isFalse);
    expect(book.trackTextFor(2), isNull);
    expect(book.audioSegmentFor(2), isNull);
  });

  test('several tracks: each has its own text, file and visibility', () {
    final book = Book(
      id: '1',
      title: 't',
      createdAt: DateTime(2026),
      sentences: const [BookSentence(text: 'a', accented: 'a', paragraph: 0)],
      tracks: [
        track(),
        track(
            language: 'pt',
            label: 'Portuguese',
            alignment: const TrackAlignment(from: [1], to: [2], confidence: [0.9])),
      ],
    );
    expect(book.trackIndexOf('pt'), 1);
    expect(book.trackIndexOf('it'), isNull);
    expect(book.trackTextFor(0, 0), 'x y');
    expect(book.trackTextFor(0, 1), 'y');
    expect(book.audioSegmentFor(0, 1)!.startMs, 100);
    final hidden = book.withTrack(book.tracks[1].copyWith(visible: false), index: 1);
    expect(Book.fromJson(hidden.toJson()).tracks[1].visible, isFalse);
    expect(hidden.withoutTrack(0).tracks.single.language, 'pt');
  });

  VideoCaptions captions(String id, String language, List<String> lines) => VideoCaptions(
        videoId: id,
        title: id,
        language: language,
        autoGenerated: true,
        cues: [
          for (var i = 0; i < lines.length; i++)
            Cue(startMs: i * 3000, durationMs: 3000, text: lines[i])
        ],
      );

  const ru = [
    'Первая фраза про лесную поляну.',
    'Вторая фраза про речную долину.',
    'Третья фраза про горную вершину.',
    'Четвертая фраза про морской берег.',
  ];
  Book russianBook() => Book(
        id: '1',
        title: 't',
        createdAt: DateTime(2026),
        sentences: [for (final r in ru) BookSentence(text: r, accented: r, paragraph: 0)],
      );

  test('AudioLinker links sentences to captions', () async {
    final linked = await const AudioLinker().link(
        russianBook(),
        captions('v', 'uk', [
          'Перша фраза про лісову поляну.',
          'Друга фраза про річкову долину.',
          'Третя фраза про гірську вершину.',
        ]));
    expect(linked.tracks.single.language, 'uk');
    expect(linked.hasAudioAt(0) && linked.hasAudioAt(1) && linked.hasAudioAt(2), isTrue);
    expect(linked.audioRangeFor(1)!.$1, 3000);
    expect(linked.trackTextFor(2), 'Третя фраза про гірську вершину.');
  });

  test('a second language adds a track, the same language replaces it', () async {
    const linker = AudioLinker();
    var book = await linker.link(russianBook(), captions('one', 'uk', ['Перша фраза про лісову поляну.']));
    book = await linker.link(book, captions('two', 'pt-BR', ['Primeira frase sobre a clareira.']));
    expect(book.tracks.map((t) => t.language), ['uk', 'pt']);
    expect(book.tracks[1].label, 'Portuguese');
    book = await linker.link(book, captions('three', 'uk', ['Друга фраза про річкову долину.']));
    expect(book.tracks, hasLength(2));
    expect(book.tracks[0].videoId, 'three');
  });

  test('a book with two audio parts: segments point at the right file', () {
    final audio = AudioTrack(
      language: 'uk',
      label: 'Ukrainian',
      parts: const [
        AudioPart(videoId: 'p1', title: 'one', from: 0),
        AudioPart(videoId: 'p2', title: 'two', from: 2),
      ],
      sentences: const [
        TimedText(text: 'a', startMs: 0, endMs: 100),
        TimedText(text: 'b', startMs: 100, endMs: 200),
        TimedText(text: 'c', startMs: 0, endMs: 50),
        TimedText(text: 'd', startMs: 50, endMs: 90),
      ],
      alignment: const TrackAlignment(from: [1, 2, 1], to: [2, 4, 3]),
    );
    final book = Book(
      id: '1',
      title: 't',
      createdAt: DateTime(2026),
      sentences: const [
        BookSentence(text: 'x', accented: 'x', paragraph: 0),
        BookSentence(text: 'y', accented: 'y', paragraph: 0),
        // Straddles both parts: only the piece in the first one plays.
        BookSentence(text: 'z', accented: 'z', paragraph: 0),
      ],
      tracks: [audio],
    );
    expect(book.audioSegmentFor(0)!.videoId, 'p1');
    final second = book.audioSegmentFor(1)!;
    expect((second.videoId, second.part, second.startMs, second.endMs), ('p2', 1, 0, 90));
    expect(book.audioSegmentFor(2)!.endMs, 200);
    expect(audio.indexAt(60, part: 1), 3);
    expect(audio.indexAt(60, part: 0), 0);
    expect(audio.indexAt(-1, part: 1), isNull);
    final back = Book.fromJson(book.toJson());
    expect(back.tracks.single.parts.map((p) => p.videoId), ['p1', 'p2']);
    expect(back.tracks.single.partOf(3), 1);
  });

  test('AudioLinker.addPart appends the next recording and keeps the first', () async {
    const linker = AudioLinker();
    var linked = await linker.link(
        russianBook(),
        captions('one', 'uk', [
          'Перша фраза про лісову поляну.',
          'Друга фраза про річкову долину.',
        ]));
    linked = await linker.addPart(
        linked,
        0,
        captions('two', 'uk', [
          'Третя фраза про гірську вершину.',
          'Четверта фраза про морський берег.',
        ]));
    final t = linked.tracks.single;
    expect(t.parts.map((p) => p.videoId), ['one', 'two']);
    expect(t.parts[1].from, 2);
    expect(linked.audioSegmentFor(0)!.videoId, 'one');
    expect(linked.audioSegmentFor(3)!.videoId, 'two');
    expect(linked.audioSegmentFor(3)!.startMs, 3000);
    expect(() => linker.addPart(linked, 0, captions('two', 'uk', ['Ще раз.'])),
        throwsA(isA<CaptionsUnavailable>()));
  });

  test('caption track choice never falls back to another language', () {
    const tracks = [('uk', true), ('uk', false), ('en', false), ('pt', true)];
    expect(chooseCaptionTrack(tracks, 'uk'), 1); // hand-made beats auto
    expect(chooseCaptionTrack(tracks, 'pt'), 3);
    expect(chooseCaptionTrack(tracks, 'it'), isNull);
    expect(chooseCaptionTrack(tracks, null), 1);
    expect(chooseCaptionTrack(const [], null), isNull);
  });

  group('a language that shares no words with Russian', () {
    // Eight sentences with their (invented) Portuguese counterparts.
    const ruText = [
      'Девочка бежала к реке и смотрела на воду.',
      'Старуха варила травяной чай для больного.',
      'Охотники вернулись из долины с добычей.',
      'Мальчик нашёл пещеру высоко в скалах.',
      'Вождь долго смотрел на огонь и молчал.',
      'Женщины собирали корни на берегу реки.',
      'Колдун приказал всем собраться у костра.',
      'Ночью пошёл снег и закрыл тропы в горах.',
    ];
    const ptText = [
      'A menina correu para o rio e olhou a água.',
      'A velha fervia chá de ervas para o doente.',
      'Os caçadores voltaram do vale com a caça.',
      'O menino achou uma caverna no alto das rochas.',
      'O chefe olhou muito tempo o fogo e calou.',
      'As mulheres colhiam raízes na margem do rio.',
      'O feiticeiro mandou todos se reunirem na fogueira.',
      'À noite nevou e cobriu as trilhas nas montanhas.',
    ];

    Book book() => Book(
          id: '1',
          title: 't',
          createdAt: DateTime(2026),
          sentences: [for (final r in ruText) BookSentence(text: r, accented: r, paragraph: 0)],
        );

    VideoCaptions pt() => VideoCaptions(
          videoId: 'pt1',
          title: 'Ayla',
          language: 'pt-BR',
          autoGenerated: true,
          cues: [
            for (var i = 0; i < ptText.length; i++)
              Cue(startMs: i * 4000, durationMs: 4000, text: ptText[i])
          ],
        );

    test('is matched through its Russian translation, which is kept', () async {
      final fake = _CountingTranslator({for (var i = 0; i < ptText.length; i++) ptText[i]: ruText[i]});
      final progress = <String>[];
      final linker = AudioLinker(translator: fake);
      var linked = await linker.link(book(), pt(), onProgress: (s, p) => progress.add(s));
      final t = linked.tracks.single;
      expect(t.language, 'pt');
      expect(t.label, 'Portuguese');
      expect(t.bridge, ruText);
      expect(fake.calls, ptText.length);
      for (var i = 0; i < ruText.length; i++) {
        expect(linked.trackTextFor(i), ptText[i], reason: 'sentence $i');
      }
      expect(progress.any((s) => s.startsWith('Translating')), isTrue);
      // Re-aligning (e.g. after a sync point) does not translate again.
      linked = await linker.relink(linked);
      expect(fake.calls, ptText.length);
    });

    test('without a translator it is still linked, only roughly', () async {
      final linked = await const AudioLinker().link(book(), pt());
      expect(linked.tracks.single.language, 'pt');
      expect(linked.tracks.single.bridge, isNull);
      expect(linked.tracks.single.sentences, hasLength(ptText.length));
    });
  });
}

class _CountingTranslator implements SentenceTranslator {
  _CountingTranslator(this.table);

  final Map<String, String> table;
  var calls = 0;

  @override
  bool get supported => true;

  @override
  Future<bool> isReady(String code) async => true;

  @override
  Future<String> translate(String text, String code) => translateBetween(text, 'ru', code);

  @override
  Future<String> translateBetween(String text, String from, String to) async {
    calls++;
    expect(to, 'ru');
    return table[text] ?? text;
  }

  @override
  Future<void> dispose() async {}
}
