import 'dart:math' as math;

import '../features/youtube/caption_models.dart';

class BookSentence {
  const BookSentence({
    required this.text,
    required this.accented,
    required this.paragraph,
    this.practiced = false,
    this.ukFrom,
    this.ukTo,
    this.confidence,
  });

  /// Sentence as found in the source.
  final String text;

  /// Text with stress marks / ё added (equals [text] when accenting is off).
  final String accented;
  final int paragraph;
  final bool practiced;

  /// Ukrainian sentences `[ukFrom, ukTo)` of [Book.ukSentences] that
  /// correspond to this sentence; null when the audio has no counterpart.
  final int? ukFrom;
  final int? ukTo;

  /// 0..1 word-overlap score of the alignment (low = probably misaligned).
  final double? confidence;

  bool get hasAudio => ukFrom != null && ukTo != null && ukTo! > ukFrom!;

  BookSentence copyWith({bool? practiced}) => BookSentence(
        text: text,
        accented: accented,
        paragraph: paragraph,
        practiced: practiced ?? this.practiced,
        ukFrom: ukFrom,
        ukTo: ukTo,
        confidence: confidence,
      );

  BookSentence withAlignment(int? from, int? to, double? confidence) =>
      BookSentence(
        text: text,
        accented: accented,
        paragraph: paragraph,
        practiced: practiced,
        ukFrom: from,
        ukTo: to,
        confidence: confidence,
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'accented': accented,
        'paragraph': paragraph,
        'practiced': practiced,
        if (ukFrom != null) 'ukFrom': ukFrom,
        if (ukTo != null) 'ukTo': ukTo,
        if (confidence != null) 'confidence': confidence,
      };

  factory BookSentence.fromJson(Map<String, dynamic> j) => BookSentence(
        text: j['text'] as String,
        accented: j['accented'] as String,
        paragraph: j['paragraph'] as int,
        practiced: j['practiced'] as bool? ?? false,
        ukFrom: j['ukFrom'] as int?,
        ukTo: j['ukTo'] as int?,
        confidence: (j['confidence'] as num?)?.toDouble(),
      );
}

/// The YouTube audiobook linked to a book.
/// One audio file of a [LinkedAudio]: the Ukrainian sentences from index
/// [from] up to the next part belong to it.
class AudioPart {
  const AudioPart({required this.videoId, required this.title, required this.from});

  final String videoId;
  final String title;
  final int from;

  Map<String, dynamic> toJson() => {'videoId': videoId, 'title': title, 'from': from};

  factory AudioPart.fromJson(Map<String, dynamic> j) => AudioPart(
      videoId: j['videoId'] as String,
      title: j['title'] as String? ?? '',
      from: j['from'] as int? ?? 0);
}

class LinkedAudio {
  const LinkedAudio({
    required this.parts,
    required this.sentences,
    this.anchors = const [],
  }) : assert(parts.length > 0);

  /// A book recorded in one file.
  LinkedAudio.single({
    required String videoId,
    required String videoTitle,
    required this.sentences,
    this.anchors = const [],
  }) : parts = [AudioPart(videoId: videoId, title: videoTitle, from: 0)];

  /// The audio files, in reading order. Their sentences follow each other in
  /// [sentences]; the times of a sentence are relative to its own file.
  final List<AudioPart> parts;

  String get videoId => parts.first.videoId;
  String get videoTitle => parts.first.title;

  /// Ukrainian sentences with their position in the audio.
  final List<TimedText> sentences;

  /// User-confirmed `(ruSentenceIndex, ukSentenceIndex)` pairs.
  final List<(int, int)> anchors;

  /// Index into [parts] of the file that holds Ukrainian sentence [uk].
  int partOf(int uk) {
    var part = 0;
    for (var k = 1; k < parts.length; k++) {
      if (parts[k].from <= uk) part = k;
    }
    return part;
  }

  /// Ukrainian sentences `[from, to)` of part [part].
  (int, int) partRange(int part) => (
        parts[part].from,
        part + 1 < parts.length ? parts[part + 1].from : sentences.length,
      );

  /// Index of the Ukrainian sentence spoken at [ms] in part [part] (the last
  /// one starting at or before it), or null before the first.
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

  LinkedAudio copyWith({
    List<TimedText>? sentences,
    List<AudioPart>? parts,
    List<(int, int)>? anchors,
  }) =>
      LinkedAudio(
        parts: parts ?? this.parts,
        sentences: sentences ?? this.sentences,
        anchors: anchors ?? this.anchors,
      );

  Map<String, dynamic> toJson() => {
        // The first part also under the old keys, so older app versions can
        // still read the book.
        'videoId': videoId,
        'videoTitle': videoTitle,
        'parts': [for (final p in parts) p.toJson()],
        'sentences': [for (final s in sentences) s.toJson()],
        'anchors': [for (final a in anchors) [a.$1, a.$2]],
      };

  factory LinkedAudio.fromJson(Map<String, dynamic> j) => LinkedAudio(
        parts: j['parts'] == null
            ? [
                AudioPart(
                    videoId: j['videoId'] as String,
                    title: j['videoTitle'] as String? ?? '',
                    from: 0)
              ]
            : [
                for (final p in j['parts'] as List)
                  AudioPart.fromJson(p as Map<String, dynamic>)
              ],
        sentences: [
          for (final s in j['sentences'] as List)
            TimedText.fromJson(s as Map<String, dynamic>)
        ],
        anchors: [
          for (final a in (j['anchors'] as List? ?? const []))
            ((a as List)[0] as int, a[1] as int)
        ],
      );
}

/// An extra language the user maintains for a book, one line per sentence
/// (empty = not written yet). Edited by hand or pasted in bulk.
class Translation {
  const Translation({required this.name, required this.lines, this.visible = true});

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

  Map<String, dynamic> toJson() => {'name': name, 'visible': visible, 'lines': lines};

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
    this.audio,
    this.translations = const [],
    this.nextPage,
  });

  final String id;
  final String title;
  final String? sourceUrl;
  final DateTime createdAt;
  final List<BookSentence> sentences;
  final LinkedAudio? audio;
  final List<Translation> translations;

  /// loveread books: the first page that has not been imported yet.
  final int? nextPage;

  int get practicedCount => sentences.where((s) => s.practiced).length;

  /// Ukrainian text for sentence [i], or null without audio link.
  String? ukrainianFor(int i) {
    final s = sentences[i];
    final a = audio;
    if (a == null || !s.hasAudio) return null;
    return a.sentences.sublist(s.ukFrom!, s.ukTo!).map((e) => e.text).join(' ');
  }

  /// Audio interval `(startMs, endMs)` of sentence [i], or null.
  (int, int)? audioRangeFor(int i) {
    final seg = audioSegmentFor(i);
    return seg == null ? null : (seg.startMs, seg.endMs);
  }

  /// The audio file and interval of sentence [i], or null. When the
  /// sentence straddles two parts only the piece in the first is returned.
  ({String videoId, int part, int startMs, int endMs})? audioSegmentFor(int i) {
    final s = sentences[i];
    final a = audio;
    if (a == null || !s.hasAudio) return null;
    final part = a.partOf(s.ukFrom!);
    final last = math.min(s.ukTo!, a.partRange(part).$2) - 1;
    return (
      videoId: a.parts[part].videoId,
      part: part,
      startMs: a.sentences[s.ukFrom!].startMs,
      endMs: a.sentences[last].endMs,
    );
  }

  /// Index of the Russian sentence whose audio contains [ms], or null.
  int? sentenceAt(int ms) {
    for (var i = 0; i < sentences.length; i++) {
      final r = audioRangeFor(i);
      if (r != null && ms >= r.$1 && ms < r.$2) return i;
    }
    return null;
  }

  Book _copy({
    List<BookSentence>? sentences,
    LinkedAudio? audio,
    bool replaceAudio = false,
    List<Translation>? translations,
    int? nextPage,
  }) =>
      Book(
        id: id,
        title: title,
        sourceUrl: sourceUrl,
        createdAt: createdAt,
        sentences: sentences ?? this.sentences,
        audio: replaceAudio ? audio : this.audio,
        translations: translations ?? this.translations,
        nextPage: nextPage ?? this.nextPage,
      );

  Book withSentences(List<BookSentence> next) => _copy(sentences: next);

  Book withTranslations(List<Translation> next) => _copy(translations: next);

  Book withAudio(LinkedAudio? next, {List<BookSentence>? sentences}) =>
      _copy(audio: next, replaceAudio: true, sentences: sentences);

  /// Adds [more] sentences at the end; every translation gets empty lines
  /// for them so indices (audio link, sync points) stay valid.
  Book appended(List<BookSentence> more, {int? nextPage}) => _copy(
        sentences: [...sentences, ...more],
        translations: [
          for (final t in translations)
            t.copyWith(lines: [...t.lines, ...List.filled(more.length, '')])
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
        if (audio != null) 'audio': audio!.toJson(),
        if (translations.isNotEmpty)
          'translations': [for (final t in translations) t.toJson()],
      };

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        id: j['id'] as String,
        title: j['title'] as String,
        sourceUrl: j['sourceUrl'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        sentences: [
          for (final s in j['sentences'] as List)
            BookSentence.fromJson(s as Map<String, dynamic>)
        ],
        audio: j['audio'] == null
            ? null
            : LinkedAudio.fromJson(j['audio'] as Map<String, dynamic>),
        translations: [
          for (final t in (j['translations'] as List? ?? const []))
            Translation.fromJson(t as Map<String, dynamic>)
        ],
        nextPage: j['nextPage'] as int?,
      );
}
