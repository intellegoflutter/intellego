/// One caption line as delivered by YouTube.
class Cue {
  const Cue({
    required this.startMs,
    required this.durationMs,
    required this.text,
  });

  final int startMs;
  final int durationMs;
  final String text;

  Map<String, dynamic> toJson() => {'s': startMs, 'd': durationMs, 't': text};

  factory Cue.fromJson(Map<String, dynamic> j) => Cue(
    startMs: j['s'] as int,
    durationMs: j['d'] as int,
    text: j['t'] as String,
  );
}

/// A sentence with the audio interval it is spoken in.
class TimedText {
  const TimedText({
    required this.text,
    required this.startMs,
    required this.endMs,
  });

  final String text;
  final int startMs;
  final int endMs;

  TimedText copyWith({String? text}) =>
      TimedText(text: text ?? this.text, startMs: startMs, endMs: endMs);

  Map<String, dynamic> toJson() => {
    'text': text,
    'start': startMs,
    'end': endMs,
  };

  factory TimedText.fromJson(Map<String, dynamic> j) => TimedText(
    text: j['text'] as String,
    startMs: j['start'] as int,
    endMs: j['end'] as int,
  );

  @override
  String toString() => 'TimedText($startMs-$endMs, $text)';
}
