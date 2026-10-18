import 'package:flutter/material.dart';

import 'pronunciation_comparer.dart';

/// Result of reading one sentence aloud: the sentence with the words that
/// went wrong marked, what was heard and the advice.
class SpeakingSheet extends StatelessWidget {
  const SpeakingSheet({
    super.key,
    required this.comparison,
    required this.heard,
    required this.feedback,
    required this.onPlayRecording,
    required this.onRetry,
    required this.onMarkPracticed,
    required this.practiced,
    required this.translations,
    required this.translating,
    this.onAddLanguages,
  });

  final Comparison comparison;
  final String heard;
  final String feedback;
  final VoidCallback onPlayRecording, onRetry, onMarkPracticed;
  final bool practiced;

  /// `(language, text)` of the sentence in the book's languages.
  final List<(String, String)> translations;
  final bool translating;

  /// Offered when the book has no language to translate into.
  final VoidCallback? onAddLanguages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final good = theme.colorScheme.primary;
    final bad = theme.colorScheme.error;
    final near = Colors.orange.shade800;
    final pct = (comparison.score * 100).round();

    TextSpan span(WordResult w) {
      switch (w.status) {
        case WordStatus.correct:
          return TextSpan(
            text: '${w.expected} ',
            style: TextStyle(color: good),
          );
        case WordStatus.misheard:
          return TextSpan(
            text: '${w.expected} ',
            style: TextStyle(
              color: w.nearMiss ? near : bad,
              decoration: TextDecoration.underline,
              decorationColor: w.nearMiss ? near : bad,
            ),
          );
        case WordStatus.missed:
          return TextSpan(
            text: '${w.expected} ',
            style: TextStyle(
              color: bad,
              decoration: TextDecoration.lineThrough,
              decorationColor: bad,
            ),
          );
        case WordStatus.extra:
          return TextSpan(
            text: '(${w.heard}) ',
            style: TextStyle(
              color: theme.colorScheme.outline,
              fontSize: 14,
              fontStyle: FontStyle.italic,
            ),
          );
      }
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  comparison.perfect
                      ? Icons.check_circle
                      : Icons.record_voice_over,
                  color: comparison.perfect
                      ? good
                      : theme.colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Text(
                  '$pct% of the words heard',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(children: [for (final w in comparison.words) span(w)]),
              style: theme.textTheme.headlineSmall?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 8),
            Text(
              heard.isEmpty ? 'Nothing was recognised.' : 'You said: $heard',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            Text(feedback, style: theme.textTheme.bodyMedium),
            if (translations.isNotEmpty ||
                translating ||
                onAddLanguages != null) ...[
              const Divider(height: 28),
              for (final (name, text) in translations)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$name: ',
                          style: TextStyle(
                            color: theme.colorScheme.outline,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: text),
                      ],
                    ),
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              if (translating)
                Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text('Translating…', style: theme.textTheme.bodySmall),
                  ],
                ),
              if (onAddLanguages != null)
                TextButton.icon(
                  onPressed: onAddLanguages,
                  icon: const Icon(Icons.translate),
                  label: const Text('Add English and Italian translations'),
                ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.mic),
                  label: const Text('Try again'),
                ),
                OutlinedButton.icon(
                  onPressed: onPlayRecording,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('My recording'),
                ),
                OutlinedButton.icon(
                  onPressed: practiced ? null : onMarkPracticed,
                  icon: const Icon(Icons.check),
                  label: Text(practiced ? 'Practised' : 'Mark as practised'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
