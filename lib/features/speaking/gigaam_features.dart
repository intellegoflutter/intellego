import 'dart:math' as math;
import 'dart:typed_data';

/// Log-mel features exactly as the GigaAM models were trained on them:
/// torchaudio's `MelSpectrogram(sample_rate=16000, n_fft=400, win_length=400,
/// hop_length=160, n_mels=64, center=True)` followed by `log(clamp(x, 1e-9, 1e9))`
/// (see gigaam/preprocess.py of github.com/salute-developers/GigaAM).
const gigaSampleRate = 16000;
const gigaMels = 64;
const _nFft = 400;
const _hop = 160;
const _bins = _nFft ~/ 2 + 1;

/// Mel filter bank as [bins][mels] flattened (torchaudio.functional.melscale_fbanks,
/// HTK scale, no normalisation).
Float64List melFilterBank() {
  double hzToMel(double f) => 2595 * math.log(1 + f / 700) / math.ln10;
  double melToHz(double m) => 700 * (math.pow(10, m / 2595) - 1);
  final mMin = hzToMel(0), mMax = hzToMel(gigaSampleRate / 2);
  final fPts = [
    for (var i = 0; i < gigaMels + 2; i++) melToHz(mMin + (mMax - mMin) * i / (gigaMels + 1))
  ];
  final fb = Float64List(_bins * gigaMels);
  for (var k = 0; k < _bins; k++) {
    final freq = (gigaSampleRate / 2) * k / (_bins - 1);
    for (var m = 0; m < gigaMels; m++) {
      final down = -(fPts[m] - freq) / (fPts[m + 1] - fPts[m]);
      final up = (fPts[m + 2] - freq) / (fPts[m + 2] - fPts[m + 1]);
      fb[k * gigaMels + m] = math.max(0, math.min(down, up));
    }
  }
  return fb;
}

/// Features for 16 kHz mono [samples] in -1..1, laid out `[mels][frames]` as
/// the model expects. [frames] is `samples.length ~/ 160 + 1`.
({Float32List data, int frames}) gigaLogMel(Float32List samples) {
  final n = samples.length;
  final frames = n ~/ _hop + 1;

  // Reflect padding by n_fft / 2 on both sides (torch pad_mode="reflect").
  final pad = _nFft ~/ 2;
  final padded = Float64List(n + 2 * pad);
  double at(int i) {
    if (n == 1) return samples[0].toDouble();
    var j = i;
    final period = 2 * (n - 1);
    j = j % period;
    if (j < 0) j += period;
    if (j >= n) j = period - j;
    return samples[j].toDouble();
  }

  for (var i = 0; i < padded.length; i++) {
    padded[i] = at(i - pad);
  }

  // Periodic Hann window.
  final window = Float64List(_nFft);
  for (var i = 0; i < _nFft; i++) {
    window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / _nFft);
  }
  // DFT tables: cos/sin of 2*pi*k*i/N, indexed (k * N + i).
  final cosT = Float64List(_bins * _nFft), sinT = Float64List(_bins * _nFft);
  for (var k = 0; k < _bins; k++) {
    for (var i = 0; i < _nFft; i++) {
      final a = 2 * math.pi * ((k * i) % _nFft) / _nFft;
      cosT[k * _nFft + i] = math.cos(a);
      sinT[k * _nFft + i] = math.sin(a);
    }
  }
  final fb = melFilterBank();

  final out = Float32List(gigaMels * frames);
  final frame = Float64List(_nFft);
  final power = Float64List(_bins);
  for (var t = 0; t < frames; t++) {
    final start = t * _hop;
    for (var i = 0; i < _nFft; i++) {
      frame[i] = padded[start + i] * window[i];
    }
    for (var k = 0; k < _bins; k++) {
      var re = 0.0, im = 0.0;
      final base = k * _nFft;
      for (var i = 0; i < _nFft; i++) {
        final v = frame[i];
        re += v * cosT[base + i];
        im -= v * sinT[base + i];
      }
      power[k] = re * re + im * im;
    }
    for (var m = 0; m < gigaMels; m++) {
      var sum = 0.0;
      for (var k = 0; k < _bins; k++) {
        sum += power[k] * fb[k * gigaMels + m];
      }
      out[m * frames + t] = math.log(sum.clamp(1e-9, 1e9));
    }
  }
  return (data: out, frames: frames);
}
