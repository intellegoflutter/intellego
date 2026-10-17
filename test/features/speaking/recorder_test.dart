import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intellego/features/speaking/recorder.dart';

void main() {
  test('pcm16ToWav writes a valid 16 kHz mono header', () {
    final pcm = Uint8List.fromList(List.generate(64, (i) => i));
    final wav = pcm16ToWav(pcm);
    final d = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 16)), 'WAVEfmt ');
    expect(d.getUint32(4, Endian.little), 36 + 64);
    expect(d.getUint16(20, Endian.little), 1);
    expect(d.getUint16(22, Endian.little), 1);
    expect(d.getUint32(24, Endian.little), 16000);
    expect(d.getUint32(28, Endian.little), 32000);
    expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    expect(d.getUint32(40, Endian.little), 64);
    expect(wav.sublist(44), pcm);
    expect(wav.length, 44 + 64);
  });
}
