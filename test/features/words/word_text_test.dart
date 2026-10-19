import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellego/features/words/word_text.dart';

const m = '́';

void main() {
  testWidgets('tapping a word reports it, tapping elsewhere does not', (
    tester,
  ) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WordText(
            text: 'Он пришё${m}л домо${m}й, 42.',
            style: null,
            saved: const {'дом'},
            onWord: tapped.add,
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.byType(Text));
    final spans = <TextSpan>[];
    text.textSpan!.visitChildren((s) {
      if (s is TextSpan) spans.add(s);
      return true;
    });
    final words = [
      for (final s in spans)
        if (s.recognizer != null) s,
    ];
    expect([for (final s in words) s.text], ['Он', 'пришё${m}л', 'домо${m}й']);
    (words[1].recognizer! as TapGestureRecognizer).onTap!();
    expect(tapped, ['пришё${m}л']);
    // "42" is not a word to look up.
    expect(spans.any((s) => s.text == '42' && s.recognizer != null), isFalse);
  });

  testWidgets('saved words are underlined', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WordText(
            text: 'Это до${m}м.',
            style: null,
            saved: const {'дом'},
            onWord: (_) {},
          ),
        ),
      ),
    );
    final spans = <TextSpan>[];
    tester.widget<Text>(find.byType(Text)).textSpan!.visitChildren((s) {
      if (s is TextSpan) spans.add(s);
      return true;
    });
    final dom = spans.firstWhere((s) => s.text == 'до${m}м');
    expect(dom.style?.decoration, TextDecoration.underline);
    final eto = spans.firstWhere((s) => s.text == 'Это');
    expect(eto.style, isNull);
  });
}
