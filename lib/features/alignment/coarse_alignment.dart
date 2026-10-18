import 'dart:math' as math;
import 'dart:typed_data';

/// Rough global alignment of two texts on blocks of roughly [blockChars]
/// characters, before the sentence-level pass.
///
/// A translation of the same book shares names and many word stems with the
/// other one, but sentence boundaries, order inside sentences and even whole
/// passages differ. Matching individual windows therefore drifts on the
/// stretches where the two texts diverge. Blocks of several sentences, weighed
/// by how rare their stems are (TF-IDF), still resemble their counterpart; a
/// monotone path through the block similarity matrix with cheap gaps and free
/// ends tolerates abridged or missing passages (the audio may cover only a part
/// of the book, or the other way round).
///
/// Returns `(ukIndex, ruIndex)` points, one per matched block pair, or null
/// when the texts are too short to be blocked.
List<(int q, int r)>? coarseAnchors(
  List<Set<int>> ru,
  List<Set<int>> uk,
  List<int> ruLen,
  List<int> ukLen, {
  int blockChars = 500,
  double matchThreshold = 0.04,
  double gapCost = 0.04,
}) {
  // Whole books on both sides would need a huge matrix: use coarser blocks.
  var rb = _blocks(ruLen, blockChars);
  var ub = _blocks(ukLen, blockChars);
  while (rb.length * ub.length > 5000000) {
    blockChars = blockChars * 3 ~/ 2;
    rb = _blocks(ruLen, blockChars);
    ub = _blocks(ukLen, blockChars);
  }
  final n = rb.length, m = ub.length;
  if (n < 4 || m < 4) return null;

  final rSets = [for (final b in rb) _union(ru, b.$1, b.$2)];
  final uSets = [for (final b in ub) _union(uk, b.$1, b.$2)];

  // Document frequency over all blocks; stems found in half of them carry no
  // information and are left out.
  final df = <int, int>{};
  for (final s in rSets) {
    for (final w in s) {
      df[w] = (df[w] ?? 0) + 1;
    }
  }
  for (final s in uSets) {
    for (final w in s) {
      df[w] = (df[w] ?? 0) + 1;
    }
  }
  final total = n + m;
  final weight = <int, double>{
    for (final e in df.entries)
      if (e.value * 2 < total) e.key: math.log(total / e.value),
  };

  double norm(Set<int> s) {
    var sum = 0.0;
    for (final w in s) {
      final x = weight[w];
      if (x != null) sum += x * x;
    }
    return sum == 0 ? 1 : math.sqrt(sum);
  }

  final rNorm = [for (final s in rSets) norm(s)];
  final uNorm = [for (final s in uSets) norm(s)];

  // Inverted index of the Ukrainian blocks.
  final postings = <int, List<int>>{};
  for (var j = 0; j < m; j++) {
    for (final w in uSets[j]) {
      if (weight.containsKey(w)) (postings[w] ??= []).add(j);
    }
  }

  // sim[i * m + j]: cosine similarity of Russian block i and Ukrainian block j.
  final sim = Float32List(n * m);
  for (var i = 0; i < n; i++) {
    for (final w in rSets[i]) {
      final x = weight[w];
      final hits = postings[w];
      if (x == null || hits == null) continue;
      for (final j in hits) {
        sim[i * m + j] += x * x;
      }
    }
    for (var j = 0; j < m; j++) {
      sim[i * m + j] /= rNorm[i] * uNorm[j];
    }
  }

  // Semi-global alignment: leading and trailing stretches of either text are
  // free, gaps in the middle cost [gapCost] per block.
  final w1 = m + 1;
  final score = Float32List((n + 1) * w1);
  final back = Uint8List(
    (n + 1) * w1,
  ); // 0 diagonal, 1 skip Russian, 2 skip Ukrainian
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final diag =
          score[(i - 1) * w1 + j - 1] +
          sim[(i - 1) * m + j - 1] -
          matchThreshold;
      final up = score[(i - 1) * w1 + j] - gapCost;
      final left = score[i * w1 + j - 1] - gapCost;
      var best = diag, move = 0;
      if (up > best) {
        best = up;
        move = 1;
      }
      if (left > best) {
        best = left;
        move = 2;
      }
      score[i * w1 + j] = best;
      back[i * w1 + j] = move;
    }
  }
  var bi = n, bj = 0;
  var bestScore = double.negativeInfinity;
  for (var j = 0; j <= m; j++) {
    if (score[n * w1 + j] > bestScore) {
      bestScore = score[n * w1 + j];
      bi = n;
      bj = j;
    }
  }
  for (var i = 0; i <= n; i++) {
    if (score[i * w1 + m] > bestScore) {
      bestScore = score[i * w1 + m];
      bi = i;
      bj = m;
    }
  }

  final points = <(int q, int r)>[];
  var i = bi, j = bj;
  while (i > 0 && j > 0) {
    final move = back[i * w1 + j];
    if (move == 0) {
      points.add((ub[j - 1].$1, rb[i - 1].$1));
      i--;
      j--;
    } else if (move == 1) {
      i--;
    } else {
      j--;
    }
  }
  return points.reversed.toList();
}

/// Consecutive index ranges `[from, to)` of about [chars] characters each.
List<(int, int)> _blocks(List<int> lengths, int chars) {
  final out = <(int, int)>[];
  var from = 0, size = 0;
  for (var i = 0; i < lengths.length; i++) {
    size += lengths[i];
    if (size >= chars) {
      out.add((from, i + 1));
      from = i + 1;
      size = 0;
    }
  }
  if (from < lengths.length) out.add((from, lengths.length));
  return out;
}

Set<int> _union(List<Set<int>> sets, int from, int to) {
  final u = <int>{};
  for (var k = from; k < to; k++) {
    u.addAll(sets[k]);
  }
  return u;
}
