import 'package:flutter/foundation.dart';

import '../../data/book.dart';
import '../youtube/cue_sentences.dart';
import '../youtube/youtube_captions.dart';
import 'sentence_aligner.dart';
import 'sentence_similarity.dart';

class _Job {
  const _Job(this.ru, this.uk, this.anchors);

  final List<String> ru;
  final List<String> uk;
  final List<(int, int)> anchors;
}

class _Aligned {
  const _Aligned(this.from, this.to, this.confidence);

  final List<int?> from;
  final List<int?> to;
  final List<double?> confidence;
}

_Aligned _run(_Job job) {
  final result = alignSentences(job.ru, job.uk, manualAnchors: job.anchors);
  final from = List<int?>.filled(job.ru.length, null);
  final to = List<int?>.filled(job.ru.length, null);
  final conf = List<double?>.filled(job.ru.length, null);
  for (final b in result.beads) {
    if (b.ukTo <= b.ukFrom || b.ruTo <= b.ruFrom) continue;
    final ukSet = <int>{};
    for (var q = b.ukFrom; q < b.ukTo; q++) {
      ukSet.addAll(stemSet(job.uk[q]));
    }
    for (var r = b.ruFrom; r < b.ruTo; r++) {
      from[r] = b.ukFrom;
      to[r] = b.ukTo;
      conf[r] = stemSimilarity(stemSet(job.ru[r]), ukSet);
    }
  }
  return _Aligned(from, to, conf);
}

/// Links a book to YouTube captions: Ukrainian sentences with timings, plus
/// for every Russian sentence the Ukrainian sentences it corresponds to.
class AudioLinker {
  const AudioLinker();

  Future<Book> link(Book book, VideoCaptions captions) {
    final uk = cuesToSentences(captions.cues);
    if (uk.isEmpty) {
      throw CaptionsUnavailable('The subtitles contain no text.');
    }
    final old = book.audio;
    return _align(
        book,
        LinkedAudio.single(
          videoId: captions.videoId,
          videoTitle: captions.title,
          sentences: uk,
          anchors: old != null && old.parts.length == 1 && old.videoId == captions.videoId
              ? old.anchors
              : const [],
        ));
  }

  /// Appends a further recording (the next part of the audiobook) after the
  /// ones already linked and aligns the whole text again. The sentences and
  /// sync points of the earlier parts keep their indices.
  Future<Book> addPart(Book book, VideoCaptions captions) {
    final audio = book.audio;
    if (audio == null) return link(book, captions);
    if (audio.parts.any((p) => p.videoId == captions.videoId)) {
      throw CaptionsUnavailable('This video is already linked to the book.');
    }
    final uk = cuesToSentences(captions.cues);
    if (uk.isEmpty) {
      throw CaptionsUnavailable('The subtitles contain no text.');
    }
    return _align(
        book,
        audio.copyWith(
          parts: [
            ...audio.parts,
            AudioPart(
                videoId: captions.videoId,
                title: captions.title,
                from: audio.sentences.length),
          ],
          sentences: [...audio.sentences, ...uk],
        ));
  }

  /// Re-runs the alignment with the book's current Ukrainian text and anchors.
  Future<Book> relink(Book book, {List<(int, int)>? anchors}) {
    final audio = book.audio;
    if (audio == null) return Future.value(book);
    return _align(book, audio.copyWith(anchors: anchors ?? audio.anchors));
  }

  Future<Book> _align(Book book, LinkedAudio audio) async {
    final aligned = await compute(
      _run,
      _Job([for (final s in book.sentences) s.text],
          [for (final s in audio.sentences) s.text], audio.anchors),
    );
    final sentences = [
      for (var i = 0; i < book.sentences.length; i++)
        book.sentences[i]
            .withAlignment(aligned.from[i], aligned.to[i], aligned.confidence[i])
    ];
    return book.withAudio(audio, sentences: sentences);
  }
}
