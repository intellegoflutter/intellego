import 'dart:convert';

import 'book.dart';

/// [next] with change times filled in: everything that differs from [old]
/// (the copy saved before) is stamped [now], everything else keeps its stamp.
/// This is how two devices later tell, sentence by sentence, whose edit is
/// the newer one. Without an [old] copy nothing is stamped.
Book stampChanges(Book? old, Book next, int now) {
  if (old == null) return next;

  final oldSentences = old.sentences;
  final sentences = [
    for (var i = 0; i < next.sentences.length; i++)
      if (i < oldSentences.length &&
          oldSentences[i].practiced == next.sentences[i].practiced)
        next.sentences[i].copyWith(practicedAt: oldSentences[i].practicedAt)
      else if (i < oldSentences.length || next.sentences[i].practiced)
        next.sentences[i].copyWith(practicedAt: now)
      else
        next.sentences[i],
  ];

  final translations = [
    for (final t in next.translations)
      () {
        final before = old.translations.where((o) => o.name == t.name);
        final o = before.isEmpty ? null : before.first;
        return t.copyWith(
          stamps: [
            for (var i = 0; i < t.lines.length; i++)
              if (o != null && i < o.lines.length && o.lines[i] == t.lines[i])
                o.stampAt(i)
              else if (t.lines[i].isEmpty && (o == null || i >= o.lines.length))
                0
              else
                now,
          ],
        );
      }(),
  ];

  final tracks = [
    for (final t in next.tracks)
      () {
        final before = old.tracks.where((o) => o.language == t.language);
        final o = before.isEmpty ? null : before.first;
        if (o != null && trackFingerprint(o) == trackFingerprint(t)) {
          return t.copyWith(updatedAt: o.updatedAt);
        }
        return t.copyWith(updatedAt: now);
      }(),
  ];

  return next
      .withSentences(sentences)
      .withTranslations(translations)
      .withTracks(tracks);
}

/// The track's content without its change time and display setting, for
/// telling whether two copies of an audiobook are the same.
String trackFingerprint(AudioTrack t) {
  final json = t.toJson()
    ..remove('updatedAt')
    ..remove('visible');
  return jsonEncode(json);
}
