import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellego/app/providers.dart';
import 'package:intellego/data/book.dart';
import 'package:intellego/features/reader/reader_font.dart';
import 'package:intellego/features/reader/reader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Books extends BooksNotifier {
  _Books(this.books);
  final List<Book> books;

  @override
  Future<List<Book>> build() async => books;
}

Book _book() => Book(
  id: '1',
  title: 'T',
  createdAt: DateTime.utc(2026),
  sentences: [
    for (var i = 0; i < 40; i++)
      BookSentence(
        text: 'Предложение номер $i',
        accented: 'Предложение номер $i',
        paragraph: 0,
      ),
  ],
  translations: [
    Translation(
      name: 'Italian',
      lines: [for (var i = 0; i < 40; i++) 'riga $i'],
    ),
  ],
);

double _russianSize(WidgetTester tester) {
  final text = tester.widget<RichText>(
    find
        .byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('Предложение'),
        )
        .first,
  );
  return text.text.style!.fontSize!;
}

double _italianSize(WidgetTester tester) {
  final text = tester.widget<RichText>(
    find
        .byWidgetPredicate(
          (w) =>
              w is RichText && w.text.toPlainText().contains('Italian: riga'),
        )
        .first,
  );
  return text.text.style!.fontSize!;
}

Future<ProviderContainer> _open(WidgetTester tester, [double? saved]) async {
  SharedPreferences.setMockInitialValues({
    if (saved != null) 'reader.fontSize': saved,
  });
  final container = ProviderContainer(
    overrides: [
      booksProvider.overrideWith(() => _Books([_book()])),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ReaderScreen(bookId: '1')),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

void main() {
  test('the size is limited and remembered', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(readerFontSizeProvider.notifier);
    expect(container.read(readerFontSizeProvider), ReaderFontSize.defaultSize);
    notifier.set(500);
    expect(container.read(readerFontSizeProvider), ReaderFontSize.max);
    notifier.set(1);
    expect(container.read(readerFontSizeProvider), ReaderFontSize.min);
    notifier.set(24);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(
      (await SharedPreferences.getInstance()).getDouble('reader.fontSize'),
      24,
    );
  });

  testWidgets('Russian and the other languages share one default size', (
    tester,
  ) async {
    await _open(tester);
    expect(_russianSize(tester), ReaderFontSize.defaultSize);
    expect(_italianSize(tester), ReaderFontSize.defaultSize);
    // smaller Russian and larger translations than the old 22 and 14
    expect(ReaderFontSize.defaultSize, lessThan(22));
    expect(ReaderFontSize.defaultSize, greaterThan(14));
  });

  testWidgets('a saved size is used', (tester) async {
    await _open(tester, 26);
    expect(_russianSize(tester), 26);
    expect(_italianSize(tester), 26);
  });

  testWidgets('Ctrl + and Ctrl - and Ctrl 0 change the size', (tester) async {
    await _open(tester);
    Future<void> ctrl(LogicalKeyboardKey key, {bool shift = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    await ctrl(LogicalKeyboardKey.equal);
    expect(_russianSize(tester), 20);
    await ctrl(LogicalKeyboardKey.equal, shift: true);
    expect(_russianSize(tester), 22);
    await ctrl(LogicalKeyboardKey.minus);
    expect(_russianSize(tester), 20);
    await ctrl(LogicalKeyboardKey.digit0);
    expect(_russianSize(tester), ReaderFontSize.defaultSize);
    await tester.pump(const Duration(seconds: 1)); // the size is saved
  });

  testWidgets(
    'Ctrl and the mouse wheel change the size, the wheel alone scrolls',
    (tester) async {
      await _open(tester);
      final centre = tester.getCenter(find.byType(ReaderScreen));
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(centre));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -60)));
      await tester.pump();
      expect(_russianSize(tester), 20);
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 60)));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 60)));
      await tester.pump();
      expect(_russianSize(tester), 16);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      final before = find.text('1');
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 300)));
      await tester.pump();
      expect(_russianSize(tester), 16);
      expect(before, findsNothing); // the list moved on
      await tester.pump(const Duration(seconds: 1)); // the size is saved
    },
  );

  testWidgets('pinching with two fingers changes the size', (tester) async {
    await _open(tester);
    final c = tester.getCenter(find.byType(ReaderScreen));
    final a = await tester.startGesture(c - const Offset(40, 0));
    final b = await tester.startGesture(c + const Offset(40, 0));
    await a.moveBy(const Offset(-40, 0));
    await b.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(_russianSize(tester), closeTo(36, 0.5)); // 80 -> 160 px apart
    await a.up();
    await b.up();
    await tester.pump(const Duration(seconds: 1)); // the size is saved
  });
}
