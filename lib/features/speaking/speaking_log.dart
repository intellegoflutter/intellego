import 'dart:convert';
import 'dart:io';

/// How often a sentence was read aloud and the best share of words heard.
class SpeakingAttempt {
  const SpeakingAttempt({required this.attempts, required this.best});

  final int attempts;
  final double best;

  SpeakingAttempt add(double score) => SpeakingAttempt(
    attempts: attempts + 1,
    best: score > best ? score : best,
  );

  Map<String, dynamic> toJson() => {'n': attempts, 'best': best};

  factory SpeakingAttempt.fromJson(Map<String, dynamic> j) => SpeakingAttempt(
    attempts: j['n'] as int? ?? 0,
    best: (j['best'] as num?)?.toDouble() ?? 0,
  );
}

/// Reading-aloud results of one book, kept in a small file of their own so
/// that saving them does not rewrite the whole book.
class SpeakingLog {
  SpeakingLog(this._file);

  final File _file;
  final Map<int, SpeakingAttempt> attempts = {};

  Future<void> load() async {
    attempts.clear();
    if (!await _file.exists()) return;
    try {
      final json =
          jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      json.forEach((k, v) {
        final i = int.tryParse(k);
        if (i != null) {
          attempts[i] = SpeakingAttempt.fromJson(v as Map<String, dynamic>);
        }
      });
    } on FormatException {
      attempts.clear(); // a damaged log is not worth failing over
    }
  }

  Future<void> record(int sentence, double score) async {
    attempts[sentence] =
        (attempts[sentence] ?? const SpeakingAttempt(attempts: 0, best: 0)).add(
          score,
        );
    await _write();
  }

  /// Replaces all results, e.g. with ones merged from another device.
  Future<void> replaceAll(Map<int, SpeakingAttempt> next) async {
    attempts
      ..clear()
      ..addAll(next);
    await _write();
  }

  Future<void> _write() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      jsonEncode({
        for (final e in attempts.entries) '${e.key}': e.value.toJson(),
      }),
    );
  }
}
