// Dev tool: aligns a whole saved book against saved captions and reports
// where the alignment drifts. Usage:
//   dart run tool/eval_align.dart <ru_pages.json> <cues.json> <out.json>
import 'dart:convert';
import 'dart:io';

import 'package:intellego/features/alignment/sentence_aligner.dart';
import 'package:intellego/features/alignment/sentence_similarity.dart';
import 'package:intellego/features/nlp/sentences/sentence_splitter.dart';
import 'package:intellego/features/youtube/caption_models.dart';
import 'package:intellego/features/youtube/cue_sentences.dart';

void main(List<String> args) {
  final skip = args.length > 3 ? double.parse(args[3]) : null;
  final dev = args.length > 4 ? double.parse(args[4]) : null;
  final band = args.length > 5 ? int.parse(args[5]) : null;
  final bc = args.length > 6 ? int.parse(args[6]) : 300;
  final tol = args.length > 9 ? int.parse(args[9]) : null;
  final pb = args.length > 10 ? int.parse(args[10]) : 30;
  final pt = args.length > 11 ? int.parse(args[11]) : 6;
  final cm = args.length > 7 ? double.parse(args[7]) : 0.04;
  final cg = args.length > 8 ? double.parse(args[8]) : 0.04;
  final pages = (jsonDecode(File(args[0]).readAsStringSync()) as List)
      .map((p) => (p as List).cast<String>())
      .toList();
  // Several recordings of one audiobook: comma-separated cue files.
  final parts = [
    for (final f in args[1].split(','))
      [
        for (final c in jsonDecode(File(f).readAsStringSync()) as List)
          Cue.fromJson(c as Map<String, dynamic>),
      ],
  ];
  final ru = [
    for (final s in const SentenceSplitter().split(
      pages.expand((p) => p).join('\n'),
    ))
      s.text,
  ];
  final uk = [
    for (final cues in parts)
      for (final t in cuesToSentences(cues)) t.text,
  ];
  stdout.writeln('ru ${ru.length} sentences, uk ${uk.length} sentences');
  final sw = Stopwatch()..start();
  final result = alignSentences(
    ru,
    uk,
    skipPenalty: skip,
    deviationPenalty: dev,
    band: band,
    tolerance: tol,
    polishBand: pb,
    polishTolerance: pt,
    coarseBlockChars: bc,
    coarseMatch: cm,
    coarseGap: cg,
  );
  stdout.writeln(
    'aligned in ${sw.elapsedMilliseconds} ms, ${result.beads.length} beads',
  );
  final from = List<int?>.filled(ru.length, null);
  final to = List<int?>.filled(ru.length, null);
  final conf = List<double>.filled(ru.length, 0);
  for (final b in result.beads) {
    if (b.ukTo <= b.ukFrom || b.ruTo <= b.ruFrom) continue;
    final u = <int>{};
    for (var q = b.ukFrom; q < b.ukTo; q++) {
      u.addAll(stemSet(uk[q]));
    }
    for (var r = b.ruFrom; r < b.ruTo; r++) {
      from[r] = b.ukFrom;
      to[r] = b.ukTo;
      conf[r] = stemSimilarity(stemSet(ru[r]), u);
    }
  }
  File(args[2]).writeAsStringSync(
    jsonEncode({'ru': ru, 'uk': uk, 'from': from, 'to': to, 'conf': conf}),
  );
}
