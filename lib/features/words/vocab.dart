import 'dart:convert';
import 'dart:io';

/// A sentence in which a word was met.
class VocabContext {
  const VocabContext({
    required this.bookId,
    required this.sentence,
    required this.text,
  });

  final String bookId;
  final int sentence;

  /// The sentence as it was when the word was saved, so it can still be shown
  /// when the book is gone.
  final String text;

  Map<String, dynamic> toJson() => {
    'book': bookId,
    'at': sentence,
    'text': text,
  };

  factory VocabContext.fromJson(Map<String, dynamic> j) => VocabContext(
    bookId: j['book'] as String,
    sentence: j['at'] as int,
    text: j['text'] as String? ?? '',
  );

  bool sameAs(VocabContext o) => o.bookId == bookId && o.sentence == sentence;
}

/// Days until a card is due again after being remembered, by box.
const reviewDays = [1, 3, 7, 14, 30, 90];

/// A word saved for practice.
class VocabEntry {
  const VocabEntry({
    required this.key,
    required this.display,
    required this.note,
    required this.contexts,
    required this.added,
    required this.due,
    this.box = 0,
  });

  /// Lower case, no stress mark: identifies the word.
  final String key;

  /// The word as written in the text, with its stress mark.
  final String display;

  /// Meaning, as the user wants to see it on the back of the card.
  final String note;
  final List<VocabContext> contexts;
  final DateTime added, due;
  final int box;

  VocabEntry copyWith({
    String? note,
    List<VocabContext>? contexts,
    DateTime? due,
    int? box,
  }) => VocabEntry(
    key: key,
    display: display,
    note: note ?? this.note,
    contexts: contexts ?? this.contexts,
    added: added,
    due: due ?? this.due,
    box: box ?? this.box,
  );

  bool isDue(DateTime now) => !due.isAfter(now);

  Map<String, dynamic> toJson() => {
    'key': key,
    'display': display,
    'note': note,
    'contexts': [for (final c in contexts) c.toJson()],
    'added': added.toIso8601String(),
    'due': due.toIso8601String(),
    'box': box,
  };

  factory VocabEntry.fromJson(Map<String, dynamic> j) => VocabEntry(
    key: j['key'] as String,
    display: j['display'] as String,
    note: j['note'] as String? ?? '',
    contexts: [
      for (final c in (j['contexts'] as List? ?? const []))
        VocabContext.fromJson(c as Map<String, dynamic>),
    ],
    added: DateTime.parse(j['added'] as String),
    due: DateTime.parse(j['due'] as String),
    box: j['box'] as int? ?? 0,
  );
}

/// The entry after a review: a remembered word moves up a box and waits
/// longer; a forgotten one goes back to the first box and is due again now.
VocabEntry scheduleNext(
  VocabEntry e, {
  required bool remembered,
  required DateTime now,
}) {
  if (!remembered) return e.copyWith(box: 0, due: now);
  final box = (e.box + 1).clamp(0, reviewDays.length);
  return e.copyWith(
    box: box,
    due: now.add(Duration(days: reviewDays[box - 1])),
  );
}

/// [entry] with [context] added unless the word was already met there.
VocabEntry withContext(VocabEntry entry, VocabContext context) =>
    entry.contexts.any(context.sameAs)
    ? entry
    : entry.copyWith(contexts: [...entry.contexts, context]);

/// The saved words, kept in one JSON file.
class VocabFile {
  VocabFile(this._file);

  final File _file;

  Future<List<VocabEntry>> load() async {
    if (!await _file.exists()) return [];
    try {
      final json =
          jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      return [
        for (final e in (json['words'] as List? ?? const []))
          VocabEntry.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return []; // a damaged file is ignored, like the speaking log
    }
  }

  Future<void> save(List<VocabEntry> entries) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      jsonEncode({
        'words': [for (final e in entries) e.toJson()],
      }),
    );
  }
}
