/// Combining acute accent placed after a stressed vowel.
const stressMark = '́';

const russianVowels = 'аеёиоуыэюяАЕЁИОУЫЭЮЯ';

abstract class Accentuator {
  /// Returns [text] with stress marks (U+0301) and/or ё added to Russian
  /// words. Words that already carry marks are left untouched.
  Future<String> accent(String text, {bool stress = true, bool yo = true});
}

class NoopAccentuator implements Accentuator {
  const NoopAccentuator();

  @override
  Future<String> accent(
    String text, {
    bool stress = true,
    bool yo = true,
  }) async => text;
}
