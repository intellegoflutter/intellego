import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Size of the text in the reader, shared by every language line and
/// remembered between sessions.
class ReaderFontSize extends Notifier<double> {
  static const defaultSize = 18.0;
  static const min = 12.0;
  static const max = 44.0;
  static const _key = 'reader.fontSize';

  Timer? _saveTimer;

  @override
  double build() {
    ref.onDispose(() => _saveTimer?.cancel());
    _load();
    return defaultSize;
  }

  Future<void> _load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getDouble(_key);
      if (saved != null && ref.mounted) state = _clamp(saved);
    } catch (_) {
      // The default size is fine without preferences.
    }
  }

  static double _clamp(double size) => size.clamp(min, max).toDouble();

  /// Sets the size (kept within limits) and remembers it shortly after the
  /// last change.
  void set(double size) {
    final next = _clamp(size);
    if (next == state) return;
    state = next;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        await (await SharedPreferences.getInstance()).setDouble(_key, next);
      } catch (_) {
        // Not worth interrupting reading for.
      }
    });
  }

  void bigger() => set(state + 2);

  void smaller() => set(state - 2);

  void reset() => set(defaultSize);
}

final readerFontSizeProvider = NotifierProvider<ReaderFontSize, double>(
  ReaderFontSize.new,
);
