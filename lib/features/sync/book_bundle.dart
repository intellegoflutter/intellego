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
