/// Greedy CTC decoding: best token per frame, repeats merged, blanks dropped.
///
/// [logProbs] is `[frames][vocab]` flattened. [tokens] maps token ids to text
/// (id 0 is the space of GigaAM's character vocabulary); the blank is
/// [blank], by convention the last id.
String ctcGreedyDecode(
  List<double> logProbs,
  int frames,
  int vocab,
  List<String> tokens, {
  int? blank,
}) {
  final blankId = blank ?? vocab - 1;
  final out = StringBuffer();
  var previous = -1;
  for (var t = 0; t < frames; t++) {
    var best = 0;
    var bestValue = logProbs[t * vocab];
    for (var v = 1; v < vocab; v++) {
      final x = logProbs[t * vocab + v];
      if (x > bestValue) {
        bestValue = x;
        best = v;
      }
    }
    if (best != previous && best != blankId) out.write(tokens[best]);
    previous = best;
  }
  return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Reads `tokens.txt` lines of the form `<token> <id>`; the space token is
/// written as an empty token followed by its id.
List<String> parseTokens(String text) {
  final byId = <int, String>{};
  for (final line in text.split('\n')) {
    if (line.trim().isEmpty && !line.startsWith(' ')) continue;
    final cut = line.lastIndexOf(' ');
    if (cut < 0) continue;
    final id = int.tryParse(line.substring(cut + 1).trim());
    if (id == null) continue;
    final token = line.substring(0, cut);
    byId[id] = token.isEmpty ? ' ' : token;
  }
  return [for (var i = 0; i < byId.length; i++) byId[i] ?? ''];
}
