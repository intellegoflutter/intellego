import 'package:flutter/foundation.dart';

import '../../data/book.dart';
import '../youtube/cue_sentences.dart';
import '../youtube/youtube_captions.dart';
import 'sentence_aligner.dart';
import '../translate/language_codes.dart';
import '../translate/sentence_translator.dart';
import 'sentence_similarity.dart';

class _Job {
  const _Job(this.ru, this.other, this.anchors, this.mode);

  final List<String> ru;

  /// The texts the Russian sentences are compared with: the track's own
  /// sentences, or their Russian translation.
  final List<String> other;
  final List<(int, int)> anchors;
  final _Compare mode;
}

/// How the Russian sentences are compared with the other texts.
enum _Compare {
  /// Word stems of Cyrillic text (Ukrainian, or a Russian translation).
  stems,

  /// Sound-alike stems of Latin-script text against transliterated Russian:
  /// names and numbers only, a weak signal.
  roughLatin,
}

_Aligned _run(_Job job) {
  final rough = job.mode == _Compare.roughLatin;
  final ruSets = [
    for (final s in job.ru) rough ? russianAsLatinStemSet(s) : stemSet(s)
  ];
  final otherSets = [
    for (final s in job.other) rough ? latinStemSet(s) : stemSet(s)
  ];
  final result = alignSentences(job.ru, job.other,
      manualAnchors: job.anchors, ruStems: ruSets, ukStems: otherSets);
  final from = List<int?>.filled(job.ru.length, null);
  final to = List<int?>.filled(job.ru.length, null);
  final conf = List<double?>.filled(job.ru.length, null);
  for (final b in result.beads) {
    if (b.ukTo <= b.ukFrom || b.ruTo <= b.ruFrom) continue;
    final otherSet = <int>{};
    for (var q = b.ukFrom; q < b.ukTo; q++) {
      otherSet.addAll(otherSets[q]);
    }
    for (var r = b.ruFrom; r < b.ruTo; r++) {
      from[r] = b.ukFrom;
      to[r] = b.ukTo;
      conf[r] = stemSimilarity(ruSets[r], otherSet);
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

/// Progress of a long step, shown to the user: what is happening and how far
/// along it is (0..1, null when unknown).
typedef LinkProgress = void Function(String status, double? progress);

/// Links a book to the YouTube captions of an audiobook: the track's sentences
/// with timings, plus for every Russian sentence the track sentences it
/// corresponds to.
class AudioLinker {
  const AudioLinker({this.translator});

  /// Translates a language that shares no words with Russian, so that it can
  /// be matched. Without one such a track is matched roughly.
  final SentenceTranslator? translator;

  /// A new track for [captions]. It replaces the track at [trackIndex] or,
  /// without one, the track already in the same language, or is added.
  Future<Book> link(Book book, VideoCaptions captions,
      {int? trackIndex, LinkProgress? onProgress}) {
    final language = baseLanguage(captions.language);
    final sentences = cuesToSentences(captions.cues, language: language);
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
    return _align(book, track, index, onProgress);
  }

  /// Appends a further recording (the next part of the audiobook) to track
  /// [trackIndex] and aligns the whole text again. The sentences and sync
  /// points of the earlier parts keep their indices.
  Future<Book> addPart(Book book, int trackIndex, VideoCaptions captions,
      {LinkProgress? onProgress}) {
    final track = book.tracks[trackIndex];
    if (track.parts.any((p) => p.videoId == captions.videoId)) {
      throw CaptionsUnavailable('This video is already linked to the book.');
    }
    final sentences = cuesToSentences(captions.cues, language: track.language);
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
          // New sentences need translating, the cache no longer fits.
          clearBridge: true,
        ),
        trackIndex,
        onProgress);
  }

  /// Re-runs the alignment of track [trackIndex] with its current text and
  /// anchors (or [anchors]); without an index, of every track.
  Future<Book> relink(Book book,
      {int? trackIndex, List<(int, int)>? anchors, LinkProgress? onProgress}) async {
    var result = book;
    for (var i = 0; i < book.tracks.length; i++) {
      if (trackIndex != null && i != trackIndex) continue;
      final track = result.tracks[i];
      result = await _align(
          result, track.copyWith(anchors: anchors ?? track.anchors), i, onProgress);
    }
    return result;
  }

  Future<Book> _align(Book book, AudioTrack track, int? index, LinkProgress? onProgress) async {
    var current = track;
    var mode = _Compare.stems;
    var other = [for (final s in track.sentences) s.text];
    if (!comparesDirectlyWithRussian(track.language)) {
      final t = translator;
      if (t != null && t.supported) {
        // Bring the track to Russian first; the translation is kept so that
        // re-aligning later does not translate again.
        final bridge = current.bridge != null && current.bridge!.length == other.length
            ? current.bridge!
            : await _translate(other, track.language, t, onProgress);
        current = current.copyWith(bridge: bridge);
        other = bridge;
      } else {
        mode = _Compare.roughLatin;
      }
    }
    onProgress?.call(
        'Matching ${book.sentences.length} sentences with ${other.length} of ${track.label}…', null);
    final aligned = await compute(
      _run,
      _Job([for (final s in book.sentences) s.text], other, current.anchors, mode),
    );
    return book.withTrack(
      current.copyWith(
          alignment: TrackAlignment(
              from: aligned.from, to: aligned.to, confidence: aligned.confidence)),
      index: index,
    );
  }

  /// Russian translation of [sentences], a few at a time.
  Future<List<String>> _translate(List<String> sentences, String language,
      SentenceTranslator translator, LinkProgress? onProgress) async {
    final out = List<String>.filled(sentences.length, '');
    const batch = 6;
    for (var i = 0; i < sentences.length; i += batch) {
      onProgress?.call('Translating to Russian for matching… $i of ${sentences.length}',
          i / sentences.length);
      final end = i + batch < sentences.length ? i + batch : sentences.length;
      final done = await Future.wait([
        for (var k = i; k < end; k++) translator.translateBetween(sentences[k], language, 'ru')
      ]);
      for (var k = i; k < end; k++) {
        out[k] = done[k - i];
      }
    }
    return out;
  }
}
