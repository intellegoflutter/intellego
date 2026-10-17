import '../nlp/sentences/sentence_splitter.dart';
import 'caption_models.dart';

/// Turns YouTube caption cues into sentences with start/end times.
///
/// Cue texts are joined into one text, split into sentences and every
/// sentence boundary is mapped back to a time inside its cue (interpolated by
/// character position). Auto-generated cues overlap, so a cue is considered
/// to end when the next one starts.
List<TimedText> cuesToSentences(List<Cue> cues, {int maxSentenceChars = 320}) {
  final sorted = [...cues]..sort((a, b) => a.startMs.compareTo(b.startMs));
  final text = StringBuffer();
  final cueStart = <int>[]; // char offset of each cue in [text]
  final cueTexts = <String>[];
  final cueFrom = <int>[], cueTo = <int>[];
  for (final c in sorted) {
    final t = c.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) continue;
    if (text.isNotEmpty) text.write(' ');
    cueStart.add(text.length);
    text.write(t);
    cueTexts.add(t);
  }
  if (cueTexts.isEmpty) return const [];
  final kept = sorted.where((c) => c.text.trim().isNotEmpty).toList();
  for (var i = 0; i < kept.length; i++) {
    final natural = kept[i].startMs + kept[i].durationMs;
    final next = i + 1 < kept.length ? kept[i + 1].startMs : natural;
    cueFrom.add(kept[i].startMs);
    cueTo.add(next > kept[i].startMs && next < natural ? next : natural);
  }

  final full = text.toString();

  int cueAt(int offset) {
    var lo = 0, hi = cueStart.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (cueStart[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  int timeAt(int offset, {required bool end}) {
    final o = end ? offset - 1 : offset;
    final i = cueAt(o.clamp(0, full.length - 1));
    final len = cueTexts[i].length;
    final within = (o - cueStart[i] + (end ? 1 : 0)).clamp(0, len);
    return cueFrom[i] + ((cueTo[i] - cueFrom[i]) * within / len).round();
  }

  final result = <TimedText>[];
  var pos = 0;
  for (final s in const SentenceSplitter().split(full)) {
    final start = full.indexOf(s.text, pos);
    if (start < 0) continue;
    final end = start + s.text.length;
    pos = end;
    if (s.text.length <= maxSentenceChars) {
      result.add(TimedText(
          text: s.text,
          startMs: timeAt(start, end: false),
          endMs: timeAt(end, end: true)));
      continue;
    }
    // Unpunctuated stretch: cut at cue boundaries.
    var chunkStart = start;
    for (var i = cueAt(start) + 1; i <= cueAt(end - 1); i++) {
      final boundary = cueStart[i];
      final last = i == cueAt(end - 1);
      if (boundary - chunkStart >= maxSentenceChars ~/ 2 || last) {
        final cut = last && end - boundary < maxSentenceChars ~/ 4 ? end : boundary;
        if (cut <= chunkStart) continue;
        result.add(TimedText(
            text: full.substring(chunkStart, cut).trim(),
            startMs: timeAt(chunkStart, end: false),
            endMs: timeAt(cut, end: true)));
        chunkStart = cut;
      }
    }
    if (chunkStart < end) {
      result.add(TimedText(
          text: full.substring(chunkStart, end).trim(),
          startMs: timeAt(chunkStart, end: false),
          endMs: timeAt(end, end: true)));
    }
  }
  return result;
}
