import 'dart:math' as math;

import '../features/youtube/caption_models.dart';

class BookSentence {
  const BookSentence({
    required this.text,
    required this.accented,
    required this.paragraph,
    this.practiced = false,
  });

  /// Sentence as found in the source.
  final String text;

  /// Text with stress marks / ё added (equals [text] when accenting is off).
  final String accented;
  final int paragraph;
  final bool practiced;

  BookSentence copyWith({bool? practiced}) => BookSentence(
    text: text,
    accented: accented,
    paragraph: paragraph,
    practiced: practiced ?? this.practiced,
  );

  Map<String, dynamic> toJson() => {
    'text': text,
    'accented': accented,
    'paragraph': paragraph,
    'practiced': practiced,
  };

  factory BookSentence.fromJson(Map<String, dynamic> j) => BookSentence(
    text: j['text'] as String,
    accented: j['accented'] as String,
    paragraph: j['paragraph'] as int,
    practiced: j['practiced'] as bool? ?? false,
  );
}

/// One audio file of an [AudioTrack]: the track sentences from index [from] up
/// to the next part belong to it.
class AudioPart {
  const AudioPart({
    required this.videoId,
    required this.title,
    required this.from,
  });

  final String videoId;
  final String title;
  final int from;

  Map<String, dynamic> toJson() => {
    'videoId': videoId,
    'title': title,
    'from': from,
  };

  factory AudioPart.fromJson(Map<String, dynamic> j) => AudioPart(
    videoId: j['videoId'] as String,
    title: j['title'] as String? ?? '',
    from: j['from'] as int? ?? 0,
  );
}

/// For every Russian sentence of the book, the track sentences `[from, to)`
/// it corresponds to (null: the audio has no counterpart) and how well the
/// words match, 0..1 (low = probably misaligned). Shorter than the book when
/// sentences were added after the last alignment; the tail is then unaligned.
class TrackAlignment {
  const TrackAlignment({
    this.from = const [],
    this.to = const [],
    this.confidence = const [],
  });

  final List<int?> from;
  final List<int?> to;
  final List<double?> confidence;

  int get length => from.length;

  bool hasAudio(int i) =>
      i < from.length && from[i] != null && to[i] != null && to[i]! > from[i]!;

  double? confidenceAt(int i) => i < confidence.length ? confidence[i] : null;

  /// Compact JSON: -1 stands for "none".
  Map<String, dynamic> toJson() => {
    'from': [for (final v in from) v ?? -1],
    'to': [for (final v in to) v ?? -1],
    'conf': [for (final v in confidence) v == null ? -1 : (v * 1000).round()],
  };

  factory TrackAlignment.fromJson(Map<String, dynamic> j) {
    List<int?> ints(String key) => [
      for (final v in (j[key] as List? ?? const [])) (v as int) < 0 ? null : v,
    ];
    return TrackAlignment(
      from: ints('from'),
      to: ints('to'),
      confidence: [
        for (final v in (j['conf'] as List? ?? const []))
          (v as int) < 0 ? null : v / 1000,
      ],
    );
  }
}

/// An audiobook of the book in one language (one or more YouTube videos).
class AudioTrack {
  const AudioTrack({
    required this.language,
    required this.label,
    required this.parts,
    required this.sentences,
    this.anchors = const [],
    this.alignment = const TrackAlignment(),
    this.visible = true,
    this.bridge,
  }) : assert(parts.length > 0);

  /// A track recorded in one file.
  AudioTrack.single({
    required this.language,
    required this.label,
    required String videoId,
    required String videoTitle,
    required this.sentences,
    this.anchors = const [],
    this.alignment = const TrackAlignment(),
    this.visible = true,
    this.bridge,
  }) : parts = [AudioPart(videoId: videoId, title: videoTitle, from: 0)];

  /// BCP-47 language code of the recording, e.g. `uk` or `pt`.
  final String language;

  /// Name shown to the user, e.g. "Ukrainian".
  final String label;

  /// The audio files, in reading order. Their sentences follow each other in
  /// [sentences]; the times of a sentence are relative to its own file.
  final List<AudioPart> parts;

  String get videoId => parts.first.videoId;
  String get videoTitle => parts.first.title;

  /// The track's sentences with their position in the audio.
  final List<TimedText> sentences;

  /// User-confirmed `(ruSentenceIndex, trackSentenceIndex)` pairs.
  final List<(int, int)> anchors;

  final TrackAlignment alignment;

  /// Whether the track is shown in the reader.
  final bool visible;

  /// Russian translation of every sentence (same length as [sentences]) used
  /// to match a language that shares no words with Russian; null when the
  /// language matches directly.
  final List<String>? bridge;

  /// Index into [parts] of the file that holds track sentence [index].
  int partOf(int index) {
    var part = 0;
    for (var k = 1; k < parts.length; k++) {
      if (parts[k].from <= index) part = k;
    }
    return part;
  }

  /// Track sentences `[from, to)` of part [part].
  (int, int) partRange(int part) => (
    parts[part].from,
    part + 1 < parts.length ? parts[part + 1].from : sentences.length,
  );

  /// Index of the track sentence spoken at [ms] in part [part] (the last one
  /// starting at or before it), or null before the first.
  int? indexAt(int ms, {int part = 0}) {
    final (from, to) = partRange(part);
    var lo = from, hi = to - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (sentences[mid].startMs <= ms) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found < 0 ? null : found;
  }

  AudioTrack copyWith({
    String? label,
    List<TimedText>? sentences,
    List<AudioPart>? parts,
    List<(int, int)>? anchors,
    TrackAlignment? alignment,
    bool? visible,
    List<String>? bridge,
    bool clearBridge = false,
  }) => AudioTrack(
    language: language,
    label: label ?? this.label,
    parts: parts ?? this.parts,
    sentences: sentences ?? this.sentences,
    anchors: anchors ?? this.anchors,
    alignment: alignment ?? this.alignment,
    visible: visible ?? this.visible,
    bridge: clearBridge ? null : (bridge ?? this.bridge),
  );

  Map<String, dynamic> toJson() => {
    'language': language,
    'label': label,
    'visible': visible,
    'parts': [for (final p in parts) p.toJson()],
    'sentences': [for (final s in sentences) s.toJson()],
    'anchors': [
      for (final a in anchors) [a.$1, a.$2],
    ],
    'alignment': alignment.toJson(),
    if (bridge != null) 'bridge': bridge,
  };

  factory AudioTrack.fromJson(
    Map<String, dynamic> j, {
    TrackAlignment? legacyAlignment,
  }) => AudioTrack(
    language: j['language'] as String? ?? 'uk',
    label: j['label'] as String? ?? 'Ukrainian',
    visible: j['visible'] as bool? ?? true,
    parts: j['parts'] == null
        ? [
            AudioPart(
              videoId: j['videoId'] as String,
              title: j['videoTitle'] as String? ?? '',
              from: 0,
            ),
          ]
        : [
            for (final p in j['parts'] as List)
              AudioPart.fromJson(p as Map<String, dynamic>),
          ],
    sentences: [
      for (final s in j['sentences'] as List)
        TimedText.fromJson(s as Map<String, dynamic>),
    ],
    anchors: [
      for (final a in (j['anchors'] as List? ?? const []))
        ((a as List)[0] as int, a[1] as int),
    ],
    alignment: j['alignment'] == null
        ? (legacyAlignment ?? const TrackAlignment())
        : TrackAlignment.fromJson(j['alignment'] as Map<String, dynamic>),
    bridge: (j['bridge'] as List?)?.cast<String>(),
  );
}

/// An extra language the user maintains for a book, one line per sentence
/// (empty = not written yet). Edited by hand or pasted in bulk.
class Translation {
  const Translation({
    required this.name,
    required this.lines,
    this.visible = true,
  });

  /// Free-form label such as "English" or "Español".
  final String name;
  final List<String> lines;
  final bool visible;

  Translation copyWith({String? name, List<String>? lines, bool? visible}) =>
      Translation(
        name: name ?? this.name,
        lines: lines ?? this.lines,
        visible: visible ?? this.visible,
      );

  Translation withLine(int i, String text) {
    final next = [...lines];
    next[i] = text.trim();
    return copyWith(lines: next);
  }

  int get filled => lines.where((l) => l.isNotEmpty).length;

  Map<String, dynamic> toJson() => {
    'name': name,
    'visible': visible,
    'lines': lines,
  };

  factory Translation.fromJson(Map<String, dynamic> j) => Translation(
    name: j['name'] as String,
    visible: j['visible'] as bool? ?? true,
    lines: (j['lines'] as List).cast<String>(),
  );
}

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.sentences,
    this.sourceUrl,
    this.tracks = const [],
    this.translations = const [],
    this.nextPage,
  });

  final String id;
  final String title;
  final String? sourceUrl;
  final DateTime createdAt;
  final List<BookSentence> sentences;

  /// Audiobooks in other languages, each aligned with the Russian sentences.
  final List<AudioTrack> tracks;
  final List<Translation> translations;

  /// loveread books: the first page that has not been imported yet.
  final int? nextPage;

  int get practicedCount => sentences.where((s) => s.practiced).length;

  bool get hasAudio => tracks.isNotEmpty;

  /// Index of the track in [language], or null.
  int? trackIndexOf(String language) {
    final i = tracks.indexWhere((t) => t.language == language);
    return i < 0 ? null : i;
  }

  /// Whether sentence [i] has a counterpart in track [track].
  bool hasAudioAt(int i, [int track = 0]) =>
      track < tracks.length && tracks[track].alignment.hasAudio(i);

  /// The text of track [track] for sentence [i], or null without a counterpart.
  String? trackTextFor(int i, [int track = 0]) {
    if (!hasAudioAt(i, track)) return null;
    final t = tracks[track];
    final a = t.alignment;
    return t.sentences
        .sublist(a.from[i]!, a.to[i]!)
        .map((e) => e.text)
        .join(' ');
  }

  /// Match score 0..1 of sentence [i] in track [track], null when unknown.
  double? confidenceAt(int i, [int track = 0]) =>
      track < tracks.length ? tracks[track].alignment.confidenceAt(i) : null;

  /// Audio interval `(startMs, endMs)` of sentence [i], or null.
  (int, int)? audioRangeFor(int i, [int track = 0]) {
    final seg = audioSegmentFor(i, track);
    return seg == null ? null : (seg.startMs, seg.endMs);
  }

  /// The audio file and interval of sentence [i] in track [track], or null.
  /// When the sentence straddles two parts only the piece in the first is
  /// returned.
  ({String videoId, int part, int startMs, int endMs})? audioSegmentFor(
    int i, [
    int track = 0,
  ]) {
    if (!hasAudioAt(i, track)) return null;
    final t = tracks[track];
    final from = t.alignment.from[i]!, to = t.alignment.to[i]!;
    final part = t.partOf(from);
    final last = math.min(to, t.partRange(part).$2) - 1;
    return (
      videoId: t.parts[part].videoId,
      part: part,
      startMs: t.sentences[from].startMs,
      endMs: t.sentences[last].endMs,
    );
  }

  Book _copy({
    List<BookSentence>? sentences,
    List<AudioTrack>? tracks,
    List<Translation>? translations,
    int? nextPage,
  }) => Book(
    id: id,
    title: title,
    sourceUrl: sourceUrl,
    createdAt: createdAt,
    sentences: sentences ?? this.sentences,
    tracks: tracks ?? this.tracks,
    translations: translations ?? this.translations,
    nextPage: nextPage ?? this.nextPage,
  );

  Book withSentences(List<BookSentence> next) => _copy(sentences: next);

  Book withTranslations(List<Translation> next) => _copy(translations: next);

  Book withTracks(List<AudioTrack> next) => _copy(tracks: next);

  /// [track] replaces the one at [index], or is added when [index] is null.
  Book withTrack(AudioTrack track, {int? index}) => withTracks([
    for (var i = 0; i < tracks.length; i++) i == index ? track : tracks[i],
    if (index == null) track,
  ]);

  Book withoutTrack(int index) => withTracks([
    for (var i = 0; i < tracks.length; i++)
      if (i != index) tracks[i],
  ]);

  /// Adds [more] sentences at the end; every translation gets empty lines
  /// for them so indices (audio links, sync points) stay valid. Track
  /// alignments simply end earlier than the book.
  Book appended(List<BookSentence> more, {int? nextPage}) => _copy(
    sentences: [...sentences, ...more],
    translations: [
      for (final t in translations)
        t.copyWith(lines: [...t.lines, ...List.filled(more.length, '')]),
    ],
    nextPage: nextPage,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'sourceUrl': sourceUrl,
    'createdAt': createdAt.toIso8601String(),
    'sentences': [for (final s in sentences) s.toJson()],
    if (nextPage != null) 'nextPage': nextPage,
    if (tracks.isNotEmpty) 'audioTracks': [for (final t in tracks) t.toJson()],
    if (translations.isNotEmpty)
      'translations': [for (final t in translations) t.toJson()],
  };

  factory Book.fromJson(Map<String, dynamic> j) {
    final rawSentences = j['sentences'] as List;
    final List<AudioTrack> tracks;
    if (j['audioTracks'] != null) {
      tracks = [
        for (final t in j['audioTracks'] as List)
          AudioTrack.fromJson(t as Map<String, dynamic>),
      ];
    } else if (j['audio'] != null) {
      // Books saved before audio tracks: one Ukrainian audiobook whose
      // alignment lived in the sentences.
      List<int?> ints(String key) => [
        for (final s in rawSentences) (s as Map<String, dynamic>)[key] as int?,
      ];
      tracks = [
        AudioTrack.fromJson(
          j['audio'] as Map<String, dynamic>,
          legacyAlignment: TrackAlignment(
            from: ints('ukFrom'),
            to: ints('ukTo'),
            confidence: [
              for (final s in rawSentences)
                ((s as Map<String, dynamic>)['confidence'] as num?)?.toDouble(),
            ],
          ),
        ),
      ];
    } else {
      tracks = const [];
    }
    return Book(
      id: j['id'] as String,
      title: j['title'] as String,
      sourceUrl: j['sourceUrl'] as String?,
      createdAt: DateTime.parse(j['createdAt'] as String),
      sentences: [
        for (final s in rawSentences)
          BookSentence.fromJson(s as Map<String, dynamic>),
      ],
      tracks: tracks,
      translations: [
        for (final t in (j['translations'] as List? ?? const []))
          Translation.fromJson(t as Map<String, dynamic>),
      ],
      nextPage: j['nextPage'] as int?,
    );
  }
}
