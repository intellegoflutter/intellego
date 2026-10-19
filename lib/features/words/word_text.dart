import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'word_tokens.dart';

/// A sentence whose words can be tapped. Words in [saved] (by [lookupForm])
/// are underlined; [trailing] follows the text.
class WordText extends StatefulWidget {
  const WordText({
    super.key,
    required this.text,
    required this.style,
    required this.saved,
    required this.onWord,
    this.trailing = const [],
  });

  final String text;
  final TextStyle? style;
  final Set<String> saved;
  final void Function(String word) onWord;
  final List<InlineSpan> trailing;

  @override
  State<WordText> createState() => _WordTextState();
}

class _WordTextState extends State<WordText> {
  final _recognizers = <TapGestureRecognizer>[];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final theme = Theme.of(context);
    final spans = <InlineSpan>[];
    var at = 0;
    for (final w in tokenizeWords(widget.text)) {
      if (w.start > at) {
        spans.add(TextSpan(text: widget.text.substring(at, w.start)));
      }
      at = w.end;
      if (!isLookupWord(w.text)) {
        spans.add(TextSpan(text: w.text));
        continue;
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onWord(w.text);
      _recognizers.add(recognizer);
      final saved = widget.saved.contains(lookupForm(w.text));
      spans.add(
        TextSpan(
          text: w.text,
          recognizer: recognizer,
          style: saved
              ? TextStyle(
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.dotted,
                  decorationColor: theme.colorScheme.primary,
                  decorationThickness: 2,
                )
              : null,
        ),
      );
    }
    if (at < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(at)));
    }
    return Text.rich(
      TextSpan(children: [...spans, ...widget.trailing]),
      style: widget.style,
    );
  }
}
