/// One sentence per line, ready to paste into an AI assistant for correction.
String exportUkrainian(Iterable<String> sentences) => sentences
    .map((s) => s.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim())
    .join('\n');

/// Lines of corrected text; a trailing blank line is ignored, blank lines in
/// the middle are kept (they mean "leave this sentence as it was").
List<String> importUkrainian(String text) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((l) => l.trim())
      .toList();
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines;
}
