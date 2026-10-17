import 'dart:math' as math;
import 'dart:typed_data';

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
/// 1. Anchors: windows of Ukrainian sentences are located in the Russian text
///    by voting on rare shared stems; a monotone chain of confident anchors
///    gives the expected path, so the audio may cover only part of the text
///    (or the text only part of the audio).
/// 2. Dynamic programming inside a band around that path over the bead types
///    1-1, 1-0, 0-1, 2-1, 1-2 and 2-2.
AlignmentResult alignSentences(
  List<String> ru,
  List<String> uk, {
  int band = 150,
  double deviationPenalty = 1.5,
  double similarityWeight = 250,
  int anchorWindow = 25,
  bool refine = false,
  List<(int ru, int uk)> manualAnchors = const [],
}) {
  if (ru.isEmpty || uk.isEmpty) {
    return AlignmentResult(const [], ruStart: 0, ruEnd: 0);
  }
  final ruSets = [for (final s in ru) stemSet(s)];
  final ukSets = [for (final s in uk) stemSet(s)];
  var path = _expectedPath(ruSets, ukSets, anchorWindow, manualAnchors);
  var result = _alignPass(ru, uk, ruSets, ukSets, path,
      band: band, deviationPenalty: deviationPenalty, similarityWeight: similarityWeight);
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
  return _alignPass(ru, uk, ruSets, ukSets, path,
      band: band ~/ 2, deviationPenalty: deviationPenalty * 2, similarityWeight: similarityWeight);
}

Set<int> _union(List<Set<int>> sets, int from, int to) {
  if (to - from == 1) return sets[from];
  final u = <int>{};
  for (var k = from; k < to; k++) {
    u.addAll(sets[k]);
  }
  return u;
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
  ({double Function(int) at, int? ruFirst, int? ruLast, int? ukFirst, int? ukLast}) path, {
  required int band,
  required double deviationPenalty,
  required double similarityWeight,
}) {
  final n = ru.length, m = uk.length;
  // centers[i]: expected Ukrainian index at Russian row i.
  final centers = Int32List(n + 1);
  for (var i = 0; i <= n; i++) {
    centers[i] = path.at(i).round().clamp(0, m);
  }

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
  final c = ruChars == 0 || ukChars == 0 ? 1.0 : ukChars / ruChars;
  final ruLen = Int32List.fromList([for (final s in ru) s.length]);
  final ukLen = Int32List.fromList([for (final s in uk) s.length]);

  const types = [(1, 1), (1, 0), (0, 1), (2, 1), (1, 2), (2, 2)];
  const penalty = [0.0, 450.0, 450.0, 230.0, 230.0, 440.0];

  final width = 2 * band + 1;
  int lo(int i) => math.max(0, centers[i] - band);
  const inf = double.infinity;
  final cost = Float32List((n + 1) * width)..fillRange(0, (n + 1) * width, inf);
  final back = Uint8List((n + 1) * width);

  int idx(int i, int j) => i * width + (j - lo(i));
  bool inBand(int i, int j) {
    final d = j - lo(i);
    return d >= 0 && d < width && j <= m;
  }

  cost[idx(0, 0)] = 0;
  for (var i = 0; i <= n; i++) {
    final jLo = lo(i);
    final jHi = math.min(m, jLo + width - 1);
    for (var j = jLo; j <= jHi; j++) {
      if (i == 0 && j == 0) continue;
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
        var total = prev +
            penalty[t] +
            _lengthCost(l1, l2, c) +
            deviationPenalty * (j - centers[i]).abs();
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
  const leftover = 60.0;
  var i = n, j = 0;
  var bestEnd = inf;
  for (var jj = math.max(0, lo(n)); jj <= math.min(m, lo(n) + width - 1); jj++) {
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
  while (i > 0 || j > 0) {
    final t = back[idx(i, j)];
    final di = types[t].$1, dj = types[t].$2;
    beads.add(Bead(i - di, i, j - dj, j));
    i -= di;
    j -= dj;
  }
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
