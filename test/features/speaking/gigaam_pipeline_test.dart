import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intellego/features/speaking/ctc_decoder.dart';
import 'package:intellego/features/speaking/gigaam_features.dart';
import 'package:intellego/features/speaking/recorder.dart';
import 'package:intellego/features/speaking/wav_reader.dart';

void main() {
  group('gigaLogMel', () {
    test('frame count follows torchaudio center=True', () {
      expect(gigaLogMel(Float32List(1600)).frames, 11);
      expect(gigaLogMel(Float32List(16000)).frames, 101);
      expect(gigaLogMel(Float32List(16000)).data.length, gigaMels * 101);
    });

    test('silence is the clamp floor', () {
      final f = gigaLogMel(Float32List(3200));
      final floor = math.log(1e-9);
      expect(f.data.every((v) => (v - floor).abs() < 1e-3), isTrue);
    });

    test('a tone lights up the mel band of its frequency', () {
      int bandOf(double hz) {
        final samples = Float32List.fromList(
            [for (var i = 0; i < 16000; i++) math.sin(2 * math.pi * hz * i / 16000) * 0.5]);
        final f = gigaLogMel(samples);
        final mid = 50; // a frame in the middle
        var best = 0;
        for (var m = 1; m < gigaMels; m++) {
          if (f.data[m * f.frames + mid] > f.data[best * f.frames + mid]) best = m;
        }
        return best;
      }

      final low = bandOf(300), mid = bandOf(1500), high = bandOf(6000);
      expect(low, lessThan(mid));
      expect(mid, lessThan(high));
      expect(high, greaterThan(50));
    });

    test('filter bank has triangles that cover the spectrum without gaps', () {
      final fb = melFilterBank();
      // Every mel band has some weight, every bin above 0 Hz up to the last
      // band centre has some.
      for (var m = 0; m < gigaMels; m++) {
        var sum = 0.0;
        for (var k = 0; k < 201; k++) {
          sum += fb[k * gigaMels + m];
        }
        expect(sum, greaterThan(0), reason: 'band $m');
      }
    });
  });

  group('ctcGreedyDecode', () {
    final tokens = [' ', 'а', 'б', '<blk>'];
    List<double> frames(List<int> best) => [
          for (final b in best) ...[for (var v = 0; v < 4; v++) v == b ? 0.0 : -5.0]
        ];

    test('merges repeats, drops blanks, keeps a repeat across a blank', () {
      // а а <blk> а б б <blk> space а
      final best = [1, 1, 3, 1, 2, 2, 3, 0, 1];
      expect(ctcGreedyDecode(frames(best), best.length, 4, tokens), 'ааб а');
    });

    test('empty and all-blank input', () {
      expect(ctcGreedyDecode(const [], 0, 4, tokens), '');
      expect(ctcGreedyDecode(frames([3, 3, 3]), 3, 4, tokens), '');
    });

    test('tokens.txt parsing keeps the space token', () {
      final t = parseTokens('  0\nа 1\nб 2\n<blk> 3\n');
      expect(t, [' ', 'а', 'б', '<blk>']);
    });
  });

  group('WAV', () {
    test('round trip through the recorder writer', () {
      final pcm = Int16List.fromList([0, 16384, -16384, 32767]).buffer.asUint8List();
      final back = readWavPcm16(pcm16ToWav(pcm));
      expect(back.sampleRate, 16000);
      expect(back.samples.length, 4);
      expect(back.samples[1], closeTo(0.5, 1e-4));
      expect(back.samples[2], closeTo(-0.5, 1e-4));
    });

    test('rejects other files', () {
      expect(() => readWavPcm16(Uint8List(10)), throwsFormatException);
    });

    test('resample changes the length by the rate ratio', () {
      final out = resample(Float32List.fromList(List.generate(480, (i) => i.toDouble())), 48000, 16000);
      expect(out.length, 160);
      expect(out[1], closeTo(3, 1e-4));
    });
  });
}
