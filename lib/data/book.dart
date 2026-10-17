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
class LinkedAudio {
  const LinkedAudio({
    required this.videoId,
    required this.videoTitle,
    required this.sentences,
    this.anchors = const [],
  });

  final String videoId;
  final String videoTitle;

  /// Ukrainian sentences with their position in the audio.
  final List<TimedText> sentences;

  /// User-confirmed `(ruSentenceIndex, ukSentenceIndex)` pairs.
  final List<(int, int)> anchors;

  /// Index of the Ukrainian sentence spoken at [ms] (the last one starting
  /// at or before it), or null before the first.
  int? indexAt(int ms) {
    var lo = 0, hi = sentences.length - 1, found = -1;
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

  LinkedAudio copyWith({List<TimedText>? sentences, List<(int, int)>? anchors}) =>
      LinkedAudio(
        videoId: videoId,
        videoTitle: videoTitle,
        sentences: sentences ?? this.sentences,
        anchors: anchors ?? this.anchors,
      );

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'videoTitle': videoTitle,
        'sentences': [for (final s in sentences) s.toJson()],
        'anchors': [for (final a in anchors) [a.$1, a.$2]],
      };

  factory LinkedAudio.fromJson(Map<String, dynamic> j) => LinkedAudio(
        videoId: j['videoId'] as String,
        videoTitle: j['videoTitle'] as String? ?? '',
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

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.sentences,
    this.sourceUrl,
    this.audio,
  });

  final String id;
  final String title;
  final String? sourceUrl;
  final DateTime createdAt;
  final List<BookSentence> sentences;
  final LinkedAudio? audio;

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
    final s = sentences[i];
    final a = audio;
    if (a == null || !s.hasAudio) return null;
    return (a.sentences[s.ukFrom!].startMs, a.sentences[s.ukTo! - 1].endMs);
  }

  /// Index of the Russian sentence whose audio contains [ms], or null.
  int? sentenceAt(int ms) {
    for (var i = 0; i < sentences.length; i++) {
      final r = audioRangeFor(i);
      if (r != null && ms >= r.$1 && ms < r.$2) return i;
    }
    return null;
  }

  Book withSentences(List<BookSentence> next) => Book(
        id: id,
        title: title,
        sourceUrl: sourceUrl,
        createdAt: createdAt,
        sentences: next,
        audio: audio,
      );

  Book withAudio(LinkedAudio? next, {List<BookSentence>? sentences}) => Book(
        id: id,
        title: title,
        sourceUrl: sourceUrl,
        createdAt: createdAt,
        sentences: sentences ?? this.sentences,
        audio: next,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'sourceUrl': sourceUrl,
        'createdAt': createdAt.toIso8601String(),
        'sentences': [for (final s in sentences) s.toJson()],
        if (audio != null) 'audio': audio!.toJson(),
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
      );
}
