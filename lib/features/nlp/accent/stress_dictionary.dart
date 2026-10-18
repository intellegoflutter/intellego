import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

/// Maps a lowercase Russian word to the index of its stressed vowel.
abstract class StressDictionary {
  Future<int?> stressIndex(String word);
}

class MapStressDictionary implements StressDictionary {
  const MapStressDictionary(this._entries);

  final Map<String, int> _entries;

  @override
  Future<int?> stressIndex(String word) async => _entries[word];
}

/// Looks words up in the sorted `stress.dat` file (lines "word\tindex") using
/// the sparse `stress.idx` (first word + byte offset of every block).
/// Keeps memory small: only the index and a few decoded blocks are in RAM.
class FileStressDictionary implements StressDictionary {
  FileStressDictionary(this._file, String indexText) {
    for (final line in const LineSplitter().convert(indexText)) {
      final tab = line.indexOf('\t');
      if (tab < 0) continue;
      _firstWords.add(line.substring(0, tab));
      _offsets.add(int.parse(line.substring(tab + 1)));
    }
  }

  static const _maxCachedBlocks = 256;

  final File _file;
  final _firstWords = <String>[];
  final _offsets = <int>[];
  final _blocks = <int, Map<String, int>>{};
  RandomAccessFile? _raf;
  int? _length;

  @override
  Future<int?> stressIndex(String word) async {
    if (_firstWords.isEmpty || word.compareTo(_firstWords.first) < 0) {
      return null;
    }
    final block = await _block(_blockFor(word));
    return block[word];
  }

  /// Last block whose first word is <= [word].
  int _blockFor(String word) {
    var lo = 0, hi = _firstWords.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_firstWords[mid].compareTo(word) <= 0) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  Future<Map<String, int>> _block(int i) async {
    final cached = _blocks.remove(i);
    if (cached != null) {
      _blocks[i] = cached; // refresh LRU position
      return cached;
    }
    final raf = _raf ??= await _file.open();
    final length = _length ??= await raf.length();
    final start = _offsets[i];
    final end = i + 1 < _offsets.length ? _offsets[i + 1] : length;
    await raf.setPosition(start);
    final Uint8List bytes = await raf.read(end - start);
    final entries = <String, int>{};
    for (final line in const LineSplitter().convert(utf8.decode(bytes))) {
      final tab = line.indexOf('\t');
      if (tab < 0) continue;
      entries[line.substring(0, tab)] = int.parse(line.substring(tab + 1));
    }
    if (_blocks.length >= _maxCachedBlocks) {
      _blocks.remove(_blocks.keys.first);
    }
    return _blocks[i] = entries;
  }

  Future<void> close() async {
    await _raf?.close();
    _raf = null;
  }
}
