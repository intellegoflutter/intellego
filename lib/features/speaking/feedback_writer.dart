import 'pronunciation_comparer.dart';

/// Turns a [Comparison] into advice for the learner. The local writer needs
/// no network; an LLM-backed one can implement the same interface.
abstract class FeedbackWriter {
  Future<String> write({required String accented, required Comparison comparison});
}

class LocalFeedbackWriter implements FeedbackWriter {
  const LocalFeedbackWriter();

  static const stressNote = 'The recognizer cannot tell a wrong stress from a right one, '
      'so check the stress marks yourself.';

  @override
  Future<String> write({required String accented, required Comparison comparison}) async {
    final lines = <String>[];
    if (comparison.perfect) {
      lines.add('Every word was recognised. $stressNote');
      return lines.join('\n');
    }
    final pct = (comparison.score * 100).round();
    lines.add('$pct% of the words were recognised.');
    for (final w in comparison.problems) {
      switch (w.status) {
        case WordStatus.missed:
          lines.add('• ${w.expected}: not heard.${_stress(w.expected!)}');
        case WordStatus.misheard:
          final how = w.nearMiss ? 'almost, heard' : 'heard';
          lines.add('• ${w.expected}: $how “${w.heard}”.${_stress(w.expected!)}');
        case WordStatus.extra:
          lines.add('• Extra word “${w.heard}”.');
        case WordStatus.correct:
          break;
      }
    }
    lines.add(stressNote);
    return lines.join('\n');
  }

  String _stress(String word) {
    final s = stressedSyllable(word);
    if (s == null || syllableCount(word) < 2) return '';
    return ' Stress on syllable $s.';
  }
}
