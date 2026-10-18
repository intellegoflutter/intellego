import 'dart:math' as math;
import 'dart:typed_data';

import 'coarse_alignment.dart';
import 'sentence_similarity.dart';

/// A group of Russian sentences `[ruFrom, ruTo)` that corresponds to a group
/// of Ukrainian sentences `[ukFrom, ukTo)`. Either side may be empty.
class Bead {
  const Bead(this.ruFrom, this.ruTo, this.ukFrom, this.ukTo);

  final int ruFrom, ruTo, ukFrom, ukTo;

  @override
  String toString() => 'Bead(ru $ruFrom-$ruTo, uk $ukFrom-$ukTo)';
}

class AlignmentResult {
  const AlignmentResult(this.beads, {required this.ruStart, required this.ruEnd});

  final List<Bead> beads;

  /// Range of Russian sentences covered by [beads].
  final int ruStart, ruEnd;
}

/// Gale–Church length-based alignment, strengthened with word-stem overlap.
///
/// 1. A block-level alignment ([coarseAnchors]) finds where the two texts
///    correspond, which tolerates passages missing from either side (the audio
///    may be abridged or cover only part of the book). Texts too short for it
///    fall back to a chain of rare-stem anchors.
/// 2. Dynamic programming over the bead types 1-1, 1-0, 0-1, 2-1, 1-2 and 2-2
///    inside a corridor around that path, pulled strongly towards it.
/// 3. The pass is repeated around its own result with a little more freedom,
///    because the block path is only accurate to a few sentences.
AlignmentResult alignSentences(
  List<String> ru,
  List<String> uk, {
  int? band,
  double? deviationPenalty,
  double similarityWeight = 250,
  double? skipPenalty,
  int? tolerance,
  bool polish = true,
  int polishBand = 30,
  int polishTolerance = 6,
  int coarseBlockChars = 300,
  double coarseMatch = 0.04,
  double coarseGap = 0.04,
  int anchorWindow = 25,
  bool refine = false,
  List<(int ru, int uk)> manualAnchors = const [],
  List<Set<int>>? ruStems,
  List<Set<int>>? ukStems,
}) {
  if (ru.isEmpty || uk.isEmpty) {
    return AlignmentResult(const [], ruStart: 0, ruEnd: 0);
  }
  // The sets the sentences are compared by: word stems of the texts unless
  // the caller supplies its own (another language, or a translation).
  final ruSets = ruStems ?? [for (final s in ru) stemSet(s)];
  final ukSets = ukStems ?? [for (final s in uk) stemSet(s)];
  final coarse = _coarsePath(ru, uk, ruSets, ukSets, manualAnchors,
      blockChars: coarseBlockChars, match: coarseMatch, gap: coarseGap);
  var path = coarse?.$1 ?? _expectedPath(ruSets, ukSets, anchorWindow, manualAnchors);
  final ratio = coarse == null ? null : _lengthRatio(ru, uk, coarse.$2);
  // The block-level path is reliable enough to hold the sentence pass close to
  // it, which also lets a whole missing passage be skipped cheaply. The
  // anchor-chain fallback needs a wide band and a gentle pull.
  band ??= coarse != null ? 60 : 150;
  deviationPenalty ??= coarse != null ? 30 : 1.5;
  skipPenalty ??= 450;
  tolerance ??= coarse != null ? 12 : 0;
  final n0 = ru.length, m0 = uk.length;
  var corridor = _corridor(coarse?.$2, path.at, n0, m0);
  var result = _alignPass(ru, uk, ruSets, ukSets, path, corridor,
      band: band,
      deviationPenalty: deviationPenalty,
      similarityWeight: similarityWeight,
      skipPenalty: skipPenalty,
      tolerance: tolerance,
      ratio: ratio);
  if (coarse != null && polish) {
    // Polish: the block path is only accurate to a few sentences, so run the
    // pass again around its own result with room to move by a few sentences.
    final points = [
      for (final b in result.beads)
        if (b.ruTo > b.ruFrom && b.ukTo > b.ukFrom) (b.ukFrom, b.ruFrom)
    ];
    final polished = _pathFromPoints(points, ru.length, uk.length);
    if (polished != null) {
      result = _alignPass(ru, uk, ruSets, ukSets, polished,
          _corridor(points, polished.at, n0, m0),
          band: math.min(band, polishBand),
          deviationPenalty: deviationPenalty,
          similarityWeight: similarityWeight,
          skipPenalty: skipPenalty,
          tolerance: polishTolerance,
          ratio: ratio);
    }
  }
  if (!refine) return result;
  // Second pass: sentences that matched convincingly become the anchors.
  final points = <(int q, int r)>[];
  for (final b in result.beads) {
    if (b.ruTo == b.ruFrom || b.ukTo == b.ukFrom) continue;
    final sim = stemSimilarity(
        _union(ruSets, b.ruFrom, b.ruTo), _union(ukSets, b.ukFrom, b.ukTo));
    if (sim >= 0.35) points.add((b.ukFrom, b.ruFrom));
  }
  final refined = _pathFromPoints(_dropOutliers(points), ru.length, uk.length);
  if (refined == null) return result;
  path = refined;
  return _alignPass(ru, uk, ruSets, ukSets, path, _corridor(null, path.at, n0, m0),
      band: band ~/ 2,
      deviationPenalty: deviationPenalty * 2,
      similarityWeight: similarityWeight,
      skipPenalty: skipPenalty,
      tolerance: 0,
      ratio: ratio);
}

/// The expected path from the block-level alignment, kept consistent with the
/// [manual] anchors; null when the texts are too short for it.
(
  ({double Function(int) at, int? ruFirst, int? ruLast, int? ukFirst, int? ukLast}) path,
  List<(int q, int r)> points,
)? _coarsePath(List<String> ru, List<String> uk, List<Set<int>> ruSets,
        List<Set<int>> ukSets, List<(int ru, int uk)> manual,
        {required int blockChars, required double match, required double gap}) {
  final points = coarseAnchors(ruSets, ukSets, [for (final s in ru) s.length],
      [for (final s in uk) s.length],
      blockChars: blockChars, matchThreshold: match, gapCost: gap);
  if (points == null || points.length < 3) return null;
  final fixed = [...manual]..sort((a, b) => a.$1.compareTo(b.$1));
  final chain = <(int q, int r)>[
    for (final p in points)
      if (fixed.every((f) => (p.$2 < f.$1) == (p.$1 < f.$2) && p.$2 != f.$1 && p.$1 != f.$2)) p,
    for (final f in fixed) (f.$2, f.$1),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  // Manual anchors may leave the chain non-monotone on the Ukrainian side.
  final mono = <(int q, int r)>[];
  for (final p in chain) {
    if (mono.isEmpty || p.$1 > mono.last.$1 && p.$2 > mono.last.$2) mono.add(p);
  }
  final path = _pathFromPoints(mono, ru.length, uk.length);
  return path == null ? null : (path, mono);
}

Set<int> _union(List<Set<int>> sets, int from, int to) {
  if (to - from == 1) return sets[from];
  final u = <int>{};
  for (var k = from; k < to; k++) {
    u.addAll(sets[k]);
  }
  return u;
}

/// For every Russian row, the range of Ukrainian indices the expected path
/// may pass through. Between two anchors that are far apart in one text only
/// (a passage missing from the other) the position inside the stretch is
/// unknown, so the whole stretch is allowed; elsewhere the path is a line.
(Int32List, Int32List) _corridor(
    List<(int q, int r)>? points, double Function(int) at, int n, int m) {
  final lo = Int32List(n + 1), hi = Int32List(n + 1);
  for (var i = 0; i <= n; i++) {
    lo[i] = hi[i] = at(i).round().clamp(0, m);
  }
  if (points != null) {
    for (var k = 0; k + 1 < points.length; k++) {
      final (q0, r0) = points[k];
      final (q1, r1) = points[k + 1];
      final dq = q1 - q0, dr = r1 - r0;
      if (dq <= 2 * dr + 12 && dr <= 2 * dq + 12) continue;
      // The block path only locates the jump to within a block or so.
      for (var i = math.max(0, r0 - 12); i <= r1 + 12 && i <= n; i++) {
        final centre = at(i).round().clamp(0, m);
        final from = math.max(q0, centre - 200).clamp(0, m);
        final to = math.min(q1, centre + 200).clamp(0, m);
        if (from > to) continue;
        lo[i] = math.min(lo[i], from);
        hi[i] = math.max(hi[i], to);
      }
    }
  }
  return (lo, hi);
}

/// Median Ukrainian-to-Russian length ratio over the stretches between
/// neighbouring anchor [points]. Stretches where one text lacks a passage
/// would skew an overall ratio, the median ignores them.
double _lengthRatio(List<String> ru, List<String> uk, List<(int q, int r)> points) {
  final ratios = <double>[];
  for (var k = 1; k < points.length; k++) {
    final dq = points[k].$1 - points[k - 1].$1, dr = points[k].$2 - points[k - 1].$2;
    if (dq <= 0 || dr <= 0 || dr > 40 || dq > 40) continue;
    var u = 0, r = 0;
    for (var j = points[k - 1].$1; j < points[k].$1; j++) {
      u += uk[j].length;
    }
    for (var i = points[k - 1].$2; i < points[k].$2; i++) {
      r += ru[i].length;
    }
    if (r > 0 && u > 0) ratios.add(u / r);
  }
  if (ratios.isEmpty) return 1;
  ratios.sort();
  return ratios[ratios.length ~/ 2];
}

/// Drops points whose Ukrainian index strays from the median of their
/// neighbours (false matches on common words).
List<(int, int)> _dropOutliers(List<(int q, int r)> pts) {
  final out = <(int, int)>[];
  const half = 8;
  for (var i = 0; i < pts.length; i++) {
    final diffs = <int>[];
    for (var k = math.max(0, i - half); k < math.min(pts.length, i + half + 1); k++) {
      diffs.add(pts[k].$1 - pts[k].$2);
    }
    diffs.sort();
    final median = diffs[diffs.length ~/ 2];
    if ((pts[i].$1 - pts[i].$2 - median).abs() <= 40) out.add(pts[i]);
  }
  return out;
}

AlignmentResult _alignPass(
  List<String> ru,
  List<String> uk,
  List<Set<int>> ruSets,
  List<Set<int>> ukSets,
  ({double Function(int) at, int? ruFirst, int? ruLast, int? ukFirst, int? ukLast}) path,
  (Int32List lo, Int32List hi) corridor, {
  required int band,
  required double deviationPenalty,
  required double similarityWeight,
  required double skipPenalty,
  required int tolerance,
  double? ratio,
}) {
  final n = ru.length, m = uk.length;
  final (cLo, cHi) = corridor;

  // Characters-per-character ratio, measured on the anchored span only.
  var ruChars = 0, ukChars = 0;
  final ruA = path.ruFirst ?? 0, ruB = path.ruLast ?? n;
  final ukA = path.ukFirst ?? 0, ukB = path.ukLast ?? m;
  for (var i = ruA; i < ruB && i < n; i++) {
    ruChars += ru[i].length;
  }
  for (var j = ukA; j < ukB && j < m; j++) {
    ukChars += uk[j].length;
  }
  final c = ratio ?? (ruChars == 0 || ukChars == 0 ? 1.0 : ukChars / ruChars);
  final ruLen = Int32List.fromList([for (final s in ru) s.length]);
  final ukLen = Int32List.fromList([for (final s in uk) s.length]);

  const types = [(1, 1), (1, 0), (0, 1), (2, 1), (1, 2), (2, 2)];
  final penalty = [0.0, skipPenalty, skipPenalty, 230.0, 230.0, 440.0];

  // Row i holds the Ukrainian columns [rowLo[i], rowHi[i]]: the corridor of the
  // expected path widened by [band].
  final rowLo = Int32List(n + 1), rowHi = Int32List(n + 1);
  final rowStart = Int32List(n + 2);
  for (var i = 0; i <= n; i++) {
    rowLo[i] = math.max(0, cLo[i] - band);
    rowHi[i] = math.min(m, cHi[i] + band);
    rowStart[i + 1] = rowStart[i] + rowHi[i] - rowLo[i] + 1;
  }
  const inf = double.infinity;
  final cost = Float32List(rowStart[n + 1])..fillRange(0, rowStart[n + 1], inf);
  final back = Uint8List(rowStart[n + 1]);

  int idx(int i, int j) => rowStart[i] + j - rowLo[i];
  bool inBand(int i, int j) => j >= rowLo[i] && j <= rowHi[i];

  // The text may start before the audio does (or the other way round).
  const leftover = 60.0;
  for (var i = 0; i <= n; i++) {
    final jLo = rowLo[i];
    final jHi = rowHi[i];
    for (var j = jLo; j <= jHi; j++) {
      if (i == 0 && j == jLo) {
        cost[idx(0, j)] = leftover * j;
        continue;
      }
      var best = inf;
      var bestT = 0;
      for (var t = 0; t < types.length; t++) {
        final di = types[t].$1, dj = types[t].$2;
        final pi = i - di, pj = j - dj;
        if (pi < 0 || pj < 0 || !inBand(pi, pj)) continue;
        final prev = cost[idx(pi, pj)];
        if (prev == inf) continue;
        var l1 = 0, l2 = 0;
        for (var k = pi; k < i; k++) {
          l1 += ruLen[k];
        }
        for (var k = pj; k < j; k++) {
          l2 += ukLen[k];
        }
        // A sentence with no counterpart costs a flat amount: the length model
        // would make a long missing passage unaffordable.
        var total = prev +
            penalty[t] +
            (t == 1 || t == 2 ? 0 : _lengthCost(l1, l2, c)) +
            deviationPenalty *
                math.max(0, math.max(cLo[i] - tolerance - j, j - cHi[i] - tolerance));
        if (di > 0 && dj > 0 && similarityWeight > 0) {
          total -= similarityWeight *
              stemSimilarity(_union(ruSets, pi, i), _union(ukSets, pj, j));
        }
        if (total < best) {
          best = total;
          bestT = t;
        }
      }
      cost[idx(i, j)] = best;
      back[idx(i, j)] = bestT;
    }
  }

  // Either text may end before the other: pick the cheapest end cell where
  // leftover sentences cost a small penalty each.
  var i = n, j = 0;
  var bestEnd = inf;
  for (var jj = rowLo[n]; jj <= rowHi[n]; jj++) {
    final total = cost[idx(n, jj)] + leftover * (m - jj);
    if (total < bestEnd) {
      bestEnd = total;
      i = n;
      j = jj;
    }
  }
  for (var ii = 0; ii <= n; ii++) {
    if (!inBand(ii, m)) continue;
    final total = cost[idx(ii, m)] + leftover * (n - ii);
    if (total < bestEnd) {
      bestEnd = total;
      i = ii;
      j = m;
    }
  }
  final endI = i, endJ = j;
  final beads = <Bead>[];
  if (endJ < m) beads.add(Bead(endI, endI, endJ, m));
  if (endI < n) beads.add(Bead(endI, n, endJ, endJ));
  while (i > 0 || (j > 0 && !(i == 0 && j == rowLo[0]))) {
    final t = back[idx(i, j)];
    final di = types[t].$1, dj = types[t].$2;
    beads.add(Bead(i - di, i, j - dj, j));
    i -= di;
    j -= dj;
  }
  if (i == 0 && j > 0) beads.add(Bead(0, 0, 0, j));
  final ordered = beads.reversed.toList();
  return AlignmentResult(ordered, ruStart: 0, ruEnd: n);
}

/// Gale–Church: -100·ln P(|δ| ≥ observed) with σ² = 6.8 per character.
double _lengthCost(int l1, int l2, double c) {
  if (l1 == 0 && l2 == 0) return 0;
  final mean = (l1 + l2 / c) / 2;
  final delta = (l2 - l1 * c) / math.sqrt(math.max(mean, 1) * 6.8);
  final p = 2 * (1 - _normalCdf(delta.abs()));
  return -100 * math.log(math.max(p, 1e-12));
}

double _normalCdf(double x) {
  // Abramowitz–Stegun 7.1.26 erf approximation.
  const a1 = 0.254829592, a2 = -0.284496736, a3 = 1.421413741;
  const a4 = -1.453152027, a5 = 1.061405429, p = 0.3275911;
  final z = x.abs() / math.sqrt2;
  final t = 1 / (1 + p * z);
  final y = 1 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * math.exp(-z * z);
  return 0.5 * (1 + (x < 0 ? -y : y));
}

/// Piecewise-linear map from a Russian sentence index to the expected
/// Ukrainian index, built from a monotone chain of confident anchors.
/// [manual] pairs `(ruIndex, ukIndex)` are trusted absolutely: automatic
/// anchors that contradict them are discarded.
({double Function(int) at, int? ruFirst, int? ruLast, int? ukFirst, int? ukLast})
    _expectedPath(List<Set<int>> ru, List<Set<int>> uk, int window,
        List<(int ru, int uk)> manual) {
  final m = uk.length, n = ru.length;
  final k = math.min(window, m);
  final index = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    for (final s in ru[i]) {
      (index[s] ??= []).add(i);
    }
  }

  // Best Russian position for the window starting at Ukrainian [q].
  (int, int) peak(int q) {
    final votes = <int, int>{};
    for (var o = 0; o < k; o++) {
      for (final s in uk[q + o]) {
        final hits = index[s];
        if (hits == null || hits.length > 15) continue;
        for (final r in hits) {
          votes[r - o] = (votes[r - o] ?? 0) + 1;
        }
      }
    }
    var bestPos = 0, bestVotes = 0;
    for (final pos in votes.keys) {
      var v = 0;
      for (var d = -3; d <= 3; d++) {
        v += votes[pos + d] ?? 0;
      }
      if (v > bestVotes) {
        bestVotes = v;
        bestPos = pos;
      }
    }
    return (bestPos, bestVotes);
  }

  const minVotes = 8;
  final stride = math.max(5, k ~/ 2);
  final anchors = <(int q, int r, int votes)>[];
  for (var q = 0; q + k <= m; q += stride) {
    final p = peak(q);
    if (p.$2 >= minVotes) anchors.add((q, p.$1, p.$2));
  }

  // Keep only automatic anchors that fit between the manual ones.
  final fixed = [...manual]..sort((a, b) => a.$1.compareTo(b.$1));
  bool consistent((int q, int r, int votes) a) {
    for (final f in fixed) {
      if ((a.$2 < f.$1) != (a.$1 < f.$2) && (a.$2 != f.$1 || a.$1 != f.$2)) return false;
    }
    return true;
  }

  if (fixed.isNotEmpty) anchors.retainWhere(consistent);
  for (final f in fixed) {
    anchors.add((f.$2, f.$1, 100000)); // heavy: always on the chain
  }
  anchors.sort((a, b) => a.$1.compareTo(b.$1));

  // Heaviest monotone chain with a plausible slope between neighbours.
  final best = List<int>.filled(anchors.length, 0);
  final prev = List<int>.filled(anchors.length, -1);
  var top = -1;
  for (var a = 0; a < anchors.length; a++) {
    best[a] = anchors[a].$3;
    for (var b = 0; b < a; b++) {
      final dq = anchors[a].$1 - anchors[b].$1;
      final dr = anchors[a].$2 - anchors[b].$2;
      if (dq <= 0 || dr <= 0) continue;
      final slope = dr / dq;
      if (dq >= 50 ? (slope < 0.3 || slope > 3) : dr > dq * 3 + 15) continue;
      if (best[b] + anchors[a].$3 > best[a]) {
        best[a] = best[b] + anchors[a].$3;
        prev[a] = b;
      }
    }
    if (top < 0 || best[a] > best[top]) top = a;
  }
  final chain = <(int q, int r)>[];
  for (var a = top; a >= 0; a = prev[a]) {
    chain.add((anchors[a].$1, anchors[a].$2));
  }
  final points = chain.reversed.toList();
  return _pathFromPoints(points, n, m) ?? (
    at: (int i) => i * m / math.max(n, 1),
    ruFirst: null, ruLast: null, ukFirst: null, ukLast: null,
  );
}

/// Piecewise-linear path through `(ukIndex, ruIndex)` [points]; null when
/// there are none.
({double Function(int) at, int? ruFirst, int? ruLast, int? ukFirst, int? ukLast})?
    _pathFromPoints(List<(int q, int r)> points, int n, int m) {
  if (points.isEmpty) return null;
  double slope;
  if (points.length >= 2) {
    slope = (points.last.$1 - points.first.$1) /
        math.max(points.last.$2 - points.first.$2, 1);
  } else {
    slope = m / math.max(n, 1);
  }
  double at(int i) {
    if (i <= points.first.$2) return points.first.$1 + (i - points.first.$2) * slope;
    if (i >= points.last.$2) return points.last.$1 + (i - points.last.$2) * slope;
    var lo = 0, hi = points.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (points[mid].$2 <= i) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final (q0, r0) = points[lo];
    final (q1, r1) = points[hi];
    return q0 + (i - r0) * (q1 - q0) / math.max(r1 - r0, 1);
  }

  return (
    at: at,
    ruFirst: points.first.$2,
    ruLast: points.last.$2,
    ukFirst: points.first.$1,
    ukLast: points.last.$1,
  );
}
