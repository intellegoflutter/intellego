import 'package:flutter/foundation.dart';

import '../../data/book.dart';
import '../youtube/cue_sentences.dart';
import '../youtube/youtube_captions.dart';
import 'sentence_aligner.dart';
import '../translate/language_codes.dart';
import 'sentence_similarity.dart';

class _Job {
  const _Job(this.ru, this.uk, this.anchors);

  final List<String> ru;

  /// The texts the Russian sentences are compared with.
  final List<String> uk;
  final List<(int, int)> anchors;
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

class _Aligned {
  const _Aligned(this.from, this.to, this.confidence);

  final List<int?> from;
  final List<int?> to;
  final List<double?> confidence;
}

/// Links a book to the YouTube captions of an audiobook: the track's sentences
/// with timings, plus for every Russian sentence the track sentences it
/// corresponds to.
class AudioLinker {
  const AudioLinker();

  /// A new track for [captions]. It replaces the track at [trackIndex] or,
  /// without one, the track already in the same language, or is added.
  Future<Book> link(Book book, VideoCaptions captions, {int? trackIndex}) {
    final language = baseLanguage(captions.language);
    final sentences = cuesToSentences(captions.cues);
    if (sentences.isEmpty) {
      throw CaptionsUnavailable('The subtitles contain no text.');
    }
    final index = trackIndex ?? book.trackIndexOf(language);
    final old = index == null ? null : book.tracks[index];
    final track = AudioTrack.single(
      language: language,
      label: languageLabelFor(language),
      videoId: captions.videoId,
      videoTitle: captions.title,
      sentences: sentences,
      visible: old?.visible ?? true,
      anchors: old != null && old.parts.length == 1 && old.videoId == captions.videoId
          ? old.anchors
          : const [],
    );
    return _align(book, track, index);
  }

  /// Appends a further recording (the next part of the audiobook) to track
  /// [trackIndex] and aligns the whole text again. The sentences and sync
  /// points of the earlier parts keep their indices.
  Future<Book> addPart(Book book, int trackIndex, VideoCaptions captions) {
    final track = book.tracks[trackIndex];
    if (track.parts.any((p) => p.videoId == captions.videoId)) {
      throw CaptionsUnavailable('This video is already linked to the book.');
    }
    final sentences = cuesToSentences(captions.cues);
    if (sentences.isEmpty) {
      throw CaptionsUnavailable('The subtitles contain no text.');
    }
    return _align(
        book,
        track.copyWith(
          parts: [
            ...track.parts,
            AudioPart(
                videoId: captions.videoId,
                title: captions.title,
                from: track.sentences.length),
          ],
          sentences: [...track.sentences, ...sentences],
        ),
        trackIndex);
  }

  /// Re-runs the alignment of track [trackIndex] with its current text and
  /// anchors (or [anchors]); without an index, of every track.
  Future<Book> relink(Book book, {int? trackIndex, List<(int, int)>? anchors}) async {
    var result = book;
    for (var i = 0; i < book.tracks.length; i++) {
      if (trackIndex != null && i != trackIndex) continue;
      final track = result.tracks[i];
      result = await _align(
          result, track.copyWith(anchors: anchors ?? track.anchors), i);
    }
    return result;
  }

  Future<Book> _align(Book book, AudioTrack track, int? index) async {
    final aligned = await compute(
      _run,
      _Job([for (final s in book.sentences) s.text],
          [for (final s in track.sentences) s.text], track.anchors),
    );
    return book.withTrack(
      track.copyWith(
          alignment: TrackAlignment(
              from: aligned.from, to: aligned.to, confidence: aligned.confidence)),
      index: index,
    );
  }
}
