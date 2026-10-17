import 'package:flutter_test/flutter_test.dart';
import 'package:intellego/features/reader/reading_position.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('top visible sentence ignores items scrolled off', () {
    expect(topVisibleIndex([(5, 0.0), (6, 0.2), (7, 0.6)]), 6);
    expect(topVisibleIndex([(9, 0.4), (10, 1.0)]), 9);
    expect(topVisibleIndex(const []), 0);
  });

  test('position is remembered per book and defaults to the start', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await ReadingPosition.load('a'), 0);
    await ReadingPosition.save('a', 1234);
    await ReadingPosition.save('b', 7);
    expect(await ReadingPosition.load('a'), 1234);
    expect(await ReadingPosition.load('b'), 7);
  });
}
