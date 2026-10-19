import 'dart:math' as math;

import '../../data/book.dart';
import '../../data/book_stamps.dart';
import '../speaking/speaking_log.dart';
import 'book_bundle.dart';

/// Sentences are compared and sent in sections of this many.
const syncSection = 256;

/// FNV-1a over the pieces fed to it; the same on every device (the Dart VM
/// has 64-bit integers everywhere the app runs).
class _Hash {
  int _h = 0xcbf29ce484222325;

  void text(String s) {
    for (final u in s.codeUnits) {
      _h = (_h ^ u) * 0x100000001b3;
    }
    _h = (_h ^ 0x1f) * 0x100000001b3;
  }

  void number(num n) => text('$n');

  int get value => _h;
}

int _hashOf(void Function(_Hash h) feed) {
  final h = _Hash();
  feed(h);
  return h.value;
}

/// A compact description of one book's state, enough to find out which
/// sections and audiobooks differ from another copy without sending them.
class BookDigest {
  const BookDigest({
    required this.sentences,
    required this.textHash,
    required this.sections,
    required this.tracks,
    required this.nextPage,
    required this.position,
    this.chapters = 0,
  });

  final int sentences;

  /// Hash of all sentence texts: equal for two copies of the same book.
  final int textHash;

  /// Hash of the changeable state (marks, translations, reading-aloud
  /// results) of each section of [syncSection] sentences.
  final List<int> sections;

  /// Content hash of each audiobook by language code.
  final Map<String, int> tracks;
  final int? nextPage;
  final int position;

  /// Hash of the chapter list.
  final int chapters;

  Map<String, dynamic> toJson() => {
    'sentences': sentences,
    'textHash': textHash,
    'sections': sections,
    'tracks': tracks,
    if (nextPage != null) 'nextPage': nextPage,
    'position': position,
    'chapters': chapters,
  };

  factory BookDigest.fromJson(Map<String, dynamic> j) => BookDigest(
    sentences: j['sentences'] as int,
    textHash: j['textHash'] as int,
    sections: (j['sections'] as List).cast<int>(),
    tracks: (j['tracks'] as Map).map((k, v) => MapEntry('$k', v as int)),
    nextPage: j['nextPage'] as int?,
    position: j['position'] as int? ?? 0,
    chapters: j['chapters'] as int? ?? 0,
  );
}

/// Hash of the texts of the first [upto] sentences.
int textHashUpTo(Book book, int upto) => _hashOf((h) {
  for (var i = 0; i < upto && i < book.sentences.length; i++) {
    h.text(book.sentences[i].text);
  }
});

BookDigest digestOf(BookBundle bundle) {
  final book = bundle.book;
  final translations = [...book.translations]
    ..sort((a, b) => a.name.compareTo(b.name));
  final count = (book.sentences.length + syncSection - 1) ~/ syncSection;
  return BookDigest(
    sentences: book.sentences.length,
    textHash: textHashUpTo(book, book.sentences.length),
    sections: [
      for (var c = 0; c < count; c++)
        _hashOf((h) {
          final end = math.min(book.sentences.length, (c + 1) * syncSection);
          for (final t in translations) {
            h.text(t.name);
          }
          for (var i = c * syncSection; i < end; i++) {
            final s = book.sentences[i];
            h.number(s.practiced ? 1 : 0);
            h.number(s.practicedAt);
            for (final t in translations) {
              h.text(i < t.lines.length ? t.lines[i] : '');
              h.number(t.stampAt(i));
            }
            final a = bundle.speaking[i];
            if (a != null) {
              h.number(a.attempts);
              h.number(a.best);
            }
          }
        }),
    ],
    tracks: {
      for (final t in book.tracks)
        t.language: _hashOf((h) => h.text(trackFingerprint(t))),
    },
    nextPage: book.nextPage,
    position: bundle.position,
    chapters: _hashOf((h) {
      for (final c in book.chapters) {
        h.number(c.sentenceIndex);
        h.text(c.title);
      }
    }),
  );
}

/// The section indices where two digests of the same book differ, counting
/// sections only one side has.
List<int> differingSections(BookDigest a, BookDigest b) => [
  for (var c = 0; c < math.max(a.sections.length, b.sections.length); c++)
    if (c >= a.sections.length ||
        c >= b.sections.length ||
        a.sections[c] != b.sections[c])
      c,
];

/// Language codes of the audiobooks that differ or that only one side has.
List<String> differingTracks(BookDigest a, BookDigest b) => [
  for (final language in {...a.tracks.keys, ...b.tracks.keys})
    if (a.tracks[language] != b.tracks[language]) language,
];

/// The changeable state of one section of sentences.
class SectionPatch {
  const SectionPatch({
    required this.from,
    required this.practiced,
    required this.practicedAt,
    required this.lines,
    required this.stamps,
    required this.speaking,
  });

  /// Index of the first sentence.
  final int from;
  final List<bool> practiced;
  final List<int> practicedAt;

  /// Translation lines and their change times by language name.
  final Map<String, List<String>> lines;
  final Map<String, List<int>> stamps;
  final Map<int, SpeakingAttempt> speaking;

  int get length => practiced.length;

  Map<String, dynamic> toJson() => {
    'from': from,
    'practiced': [for (final p in practiced) p ? 1 : 0],
    'practicedAt': practicedAt,
    'lines': lines,
    'stamps': stamps,
    'speaking': {
      for (final e in speaking.entries) '${e.key}': e.value.toJson(),
    },
  };

  factory SectionPatch.fromJson(Map<String, dynamic> j) => SectionPatch(
    from: j['from'] as int,
    practiced: [for (final p in j['practiced'] as List) p == 1],
    practicedAt: (j['practicedAt'] as List).cast<int>(),
    lines: {
      for (final e in (j['lines'] as Map).entries)
        '${e.key}': (e.value as List).cast<String>(),
    },
    stamps: {
      for (final e in (j['stamps'] as Map).entries)
        '${e.key}': (e.value as List).cast<int>(),
    },
    speaking: {
      for (final e in (j['speaking'] as Map).entries)
        int.parse('${e.key}'): SpeakingAttempt.fromJson(
          e.value as Map<String, dynamic>,
        ),
    },
  );
}

/// What one device sends the other: the sections and audiobooks that differ,
/// sentences the other does not have yet, and the small per-book settings.
class BookPatch {
  const BookPatch({
    this.tailFrom,
    this.tail = const [],
    this.sections = const [],
    this.tracks = const [],
    this.nextPage,
    this.position = 0,
    this.chapters = const [],
  });

  /// Index of the first of [tail], sentences added at the end of the book.
  final int? tailFrom;
  final List<BookSentence> tail;
  final List<SectionPatch> sections;
  final List<AudioTrack> tracks;
  final int? nextPage;
  final int position;

  /// The book's chapters; joined with the other copy's by sentence.
  final List<Chapter> chapters;

  Map<String, dynamic> toJson() => {
    if (tailFrom != null) 'tailFrom': tailFrom,
    if (tail.isNotEmpty) 'tail': [for (final s in tail) s.toJson()],
    'sections': [for (final s in sections) s.toJson()],
    'tracks': [for (final t in tracks) t.toJson()],
    if (nextPage != null) 'nextPage': nextPage,
    'position': position,
    if (chapters.isNotEmpty) 'chapters': [for (final c in chapters) c.toJson()],
  };

  factory BookPatch.fromJson(Map<String, dynamic> j) => BookPatch(
    tailFrom: j['tailFrom'] as int?,
    tail: [
      for (final s in (j['tail'] as List? ?? const []))
        BookSentence.fromJson(s as Map<String, dynamic>),
    ],
    sections: [
      for (final s in j['sections'] as List)
        SectionPatch.fromJson(s as Map<String, dynamic>),
    ],
    tracks: [
      for (final t in j['tracks'] as List)
        AudioTrack.fromJson(t as Map<String, dynamic>),
    ],
    nextPage: j['nextPage'] as int?,
    position: j['position'] as int? ?? 0,
    chapters: [
      for (final c in (j['chapters'] as List? ?? const []))
        Chapter.fromJson(c as Map<String, dynamic>),
    ],
  );
}

/// The pieces of [bundle] that are asked for: the [sections] by index, the
/// audiobooks by language code, and the sentences from [tailFrom] on.
BookPatch buildPatch(
  BookBundle bundle, {
  Iterable<int> sections = const [],
  Iterable<String> tracks = const [],
  int? tailFrom,
}) {
  final book = bundle.book;
  final n = book.sentences.length;
  return BookPatch(
    tailFrom: tailFrom != null && tailFrom < n ? tailFrom : null,
    tail: tailFrom != null && tailFrom < n
        ? book.sentences.sublist(tailFrom)
        : const [],
    sections: [
      for (final c in sections)
        if (c * syncSection < n)
          () {
            final from = c * syncSection;
            final to = math.min(n, from + syncSection);
            return SectionPatch(
              from: from,
              practiced: [
                for (var i = from; i < to; i++) book.sentences[i].practiced,
              ],
              practicedAt: [
                for (var i = from; i < to; i++) book.sentences[i].practicedAt,
              ],
              lines: {
                for (final t in book.translations)
                  t.name: [
                    for (var i = from; i < to; i++)
                      i < t.lines.length ? t.lines[i] : '',
                  ],
              },
              stamps: {
                for (final t in book.translations)
                  t.name: [for (var i = from; i < to; i++) t.stampAt(i)],
              },
              speaking: {
                for (var i = from; i < to; i++)
                  if (bundle.speaking[i] != null) i: bundle.speaking[i]!,
              },
            );
          }(),
    ],
    tracks: [
      for (final t in book.tracks)
        if (tracks.contains(t.language)) t,
    ],
    nextPage: book.nextPage,
    position: bundle.position,
    chapters: book.chapters,
  );
}

/// Which of two values written at [mineAt] and [theirsAt] wins; the same
/// answer on both devices, also for equal times.
bool _theirsWinsLine(String mine, int mineAt, String theirs, int theirsAt) {
  if (theirsAt != mineAt) return theirsAt > mineAt;
  if (mine == theirs) return false;
  if (mine.isEmpty != theirs.isEmpty) return mine.isEmpty;
  return theirs.compareTo(mine) > 0;
}

bool _theirsWinsTrack(AudioTrack mine, AudioTrack theirs) {
  if (theirs.updatedAt != mine.updatedAt) {
    return theirs.updatedAt > mine.updatedAt;
  }
  return trackFingerprint(theirs).compareTo(trackFingerprint(mine)) > 0;
}

/// Both chapter lists together; where both start a chapter at the same
/// sentence the greater title wins, so both devices end with the same list.
/// A chapter removed on one device comes back from the other.
List<Chapter> _joinChapters(List<Chapter> mine, List<Chapter> theirs) {
  final byIndex = <int, Chapter>{};
  for (final c in [...mine, ...theirs]) {
    final o = byIndex[c.sentenceIndex];
    if (o == null || c.title.compareTo(o.title) > 0) {
      byIndex[c.sentenceIndex] = c;
    }
  }
  return [for (final i in byIndex.keys.toList()..sort()) byIndex[i]!];
}

/// [mine] joined with what [patch] carries, judged item by item: the newer
/// change to a sentence mark, a translation line or an audiobook wins, new
/// sentences, languages and audiobooks are added, reading-aloud results keep
/// the larger numbers. Applying the patches of two devices to each other
/// leaves both with the same state.
///
/// Throws a [StateError] when the patch continues the book after sentences
/// this copy does not have.
BookBundle applyPatch(BookBundle mine, BookPatch patch) {
  var book = mine.book;

  final tailFrom = patch.tailFrom;
  if (tailFrom != null && patch.tail.isNotEmpty) {
    if (tailFrom > book.sentences.length) {
      throw StateError('The other copy continues after sentence $tailFrom.');
    }
    final skip = book.sentences.length - tailFrom;
    if (skip < patch.tail.length) {
      book = book.appended(patch.tail.sublist(skip));
    }
  }
  final n = book.sentences.length;

  final sentences = [...book.sentences];
  final translations = [
    for (final t in book.translations)
      (
        t.name,
        t,
        [for (var i = 0; i < n; i++) i < t.lines.length ? t.lines[i] : ''],
        [for (var i = 0; i < n; i++) t.stampAt(i)],
      ),
  ];
  final speaking = {...mine.speaking};

  for (final s in patch.sections) {
    for (var j = 0; j < s.length && s.from + j < n; j++) {
      final i = s.from + j;
      final m = sentences[i];
      final theirsAt = s.practicedAt[j];
      final theirsMark = s.practiced[j];
      final bool mark;
      final int at;
      if (theirsAt != m.practicedAt) {
        final theirs = theirsAt > m.practicedAt;
        mark = theirs ? theirsMark : m.practiced;
        at = theirs ? theirsAt : m.practicedAt;
      } else {
        mark = m.practiced || theirsMark;
        at = m.practicedAt;
      }
      if (mark != m.practiced || at != m.practicedAt) {
        sentences[i] = m.copyWith(practiced: mark, practicedAt: at);
      }
    }
    for (final e in s.lines.entries) {
      var k = translations.indexWhere((t) => t.$1 == e.key);
      if (k < 0) {
        translations.add((
          e.key,
          Translation(name: e.key, lines: const []),
          List.filled(n, ''),
          List.filled(n, 0),
        ));
        k = translations.length - 1;
      }
      final lines = translations[k].$3, stamps = translations[k].$4;
      final theirStamps = s.stamps[e.key] ?? const <int>[];
      for (var j = 0; j < e.value.length && s.from + j < n; j++) {
        final i = s.from + j;
        final theirsAt = j < theirStamps.length ? theirStamps[j] : 0;
        if (_theirsWinsLine(lines[i], stamps[i], e.value[j], theirsAt)) {
          lines[i] = e.value[j];
          stamps[i] = theirsAt;
        }
      }
    }
    for (final e in s.speaking.entries) {
      if (e.key >= n) continue;
      final a = speaking[e.key];
      speaking[e.key] = SpeakingAttempt(
        attempts: math.max(a?.attempts ?? 0, e.value.attempts),
        best: math.max(a?.best ?? 0, e.value.best),
      );
    }
  }

  final tracks = [...book.tracks];
  for (final t in patch.tracks) {
    final k = tracks.indexWhere((o) => o.language == t.language);
    if (k < 0) {
      tracks.add(t);
    } else if (_theirsWinsTrack(tracks[k], t)) {
      tracks[k] = t.copyWith(visible: tracks[k].visible);
    }
  }

  final pages = [book.nextPage, patch.nextPage].whereType<int>();
  return BookBundle(
    book: Book(
      id: book.id,
      title: book.title,
      sourceUrl: book.sourceUrl,
      createdAt: book.createdAt,
      sentences: sentences,
      tracks: tracks,
      translations: [
        for (final (_, t, lines, stamps) in translations)
          t.copyWith(lines: lines, stamps: stamps),
      ],
      chapters: _joinChapters(book.chapters, patch.chapters),
      nextPage: pages.isEmpty ? null : pages.reduce(math.max),
      updatedAt: book.updatedAt,
    ),
    speaking: speaking,
    position: math.max(mine.position, patch.position),
  );
}
