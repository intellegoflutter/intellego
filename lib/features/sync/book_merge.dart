import 'dart:math' as math;

import '../../data/book.dart';
import '../speaking/speaking_log.dart';

/// Everything that is kept in step between two devices for one book.
class BookBundle {
  const BookBundle({
    required this.book,
    this.speaking = const {},
    this.position = 0,
  });

  final Book book;

  /// Reading-aloud results by sentence index.
  final Map<int, SpeakingAttempt> speaking;

  /// Sentence at the top of the reader.
  final int position;

  Map<String, dynamic> toJson() => {
    'book': book.toJson(),
    'speaking': {
      for (final k in speaking.keys.toList()..sort())
        '$k': speaking[k]!.toJson(),
    },
    'position': position,
  };

  factory BookBundle.fromJson(Map<String, dynamic> j) => BookBundle(
    book: Book.fromJson(j['book'] as Map<String, dynamic>),
    speaking: {
      for (final e in (j['speaking'] as Map? ?? const {}).entries)
        int.parse(e.key as String): SpeakingAttempt.fromJson(
          e.value as Map<String, dynamic>,
        ),
    },
    position: j['position'] as int? ?? 0,
  );
}

/// The two copies of one book joined into one that contains the work of both.
///
/// The copy saved last is the primary one: where both changed the same thing
/// (a translation line, a track) its version is kept. Anything only the other
/// copy has (lines the primary left empty, languages, audiobooks, sentences
/// added at the end, practised marks) is added. Order does not matter, apart
/// from which copy wins when they were saved at the very same time ([theirs]).
BookBundle mergeBundles(BookBundle mine, BookBundle theirs) => BookBundle(
  book: mergeBooks(mine.book, theirs.book),
  speaking: _mergeSpeaking(mine.speaking, theirs.speaking),
  position: math.max(mine.position, theirs.position),
);

Book mergeBooks(Book mine, Book theirs) {
  final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  final mineWins = (mine.updatedAt ?? epoch).isAfter(theirs.updatedAt ?? epoch);
  final primary = mineWins ? mine : theirs;
  final other = mineWins ? theirs : mine;

  final shared = math.min(primary.sentences.length, other.sentences.length);
  for (var i = 0; i < shared; i++) {
    if (primary.sentences[i].text != other.sentences[i].text) {
      // Not the same text any more (re-imported?): nothing to join.
      return primary;
    }
  }

  final longer = primary.sentences.length >= other.sentences.length
      ? primary
      : other;
  final sentences = [
    for (var i = 0; i < longer.sentences.length; i++)
      if (i < shared)
        primary.sentences[i].copyWith(
          practiced:
              primary.sentences[i].practiced || other.sentences[i].practiced,
        )
      else
        longer.sentences[i],
  ];

  List<String> padded(List<String> lines) => [
    for (var i = 0; i < sentences.length; i++) i < lines.length ? lines[i] : '',
  ];
  final translations = <Translation>[
    for (final t in primary.translations)
      () {
        final o = other.translations.where((o) => o.name == t.name).firstOrNull;
        final mine = padded(t.lines), theirs = padded(o?.lines ?? const []);
        return t.copyWith(
          lines: [
            for (var i = 0; i < mine.length; i++)
              mine[i].isNotEmpty ? mine[i] : theirs[i],
          ],
        );
      }(),
    for (final o in other.translations)
      if (!primary.translations.any((t) => t.name == o.name))
        o.copyWith(lines: padded(o.lines)),
  ];

  final tracks = [
    ...primary.tracks,
    for (final o in other.tracks)
      if (!primary.tracks.any((t) => t.language == o.language)) o,
  ];

  final pages = [primary.nextPage, other.nextPage].whereType<int>();
  final stamps = [primary.updatedAt, other.updatedAt].whereType<DateTime>();
  return Book(
    id: primary.id,
    title: primary.title,
    sourceUrl: primary.sourceUrl,
    createdAt: primary.createdAt,
    sentences: sentences,
    tracks: tracks,
    translations: translations,
    nextPage: pages.isEmpty ? null : pages.reduce(math.max),
    updatedAt: stamps.isEmpty
        ? null
        : stamps.reduce((a, b) => a.isAfter(b) ? a : b),
  );
}

Map<int, SpeakingAttempt> _mergeSpeaking(
  Map<int, SpeakingAttempt> a,
  Map<int, SpeakingAttempt> b,
) => {
  for (final k in {...a.keys, ...b.keys})
    k: SpeakingAttempt(
      attempts: math.max(a[k]?.attempts ?? 0, b[k]?.attempts ?? 0),
      best: math.max(a[k]?.best ?? 0, b[k]?.best ?? 0),
    ),
};
