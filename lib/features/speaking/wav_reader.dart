import 'dart:io';
import 'dart:typed_data';

/// Mono samples in -1..1 and their sample rate.
class Pcm {
  const Pcm(this.samples, this.sampleRate);

  final Float32List samples;
  final int sampleRate;
}

/// Reads a 16-bit PCM WAV (channels are averaged). Throws [FormatException]
/// for anything else.
Pcm readWavPcm16(Uint8List bytes) {
  final d = ByteData.sublistView(bytes);
  if (bytes.length < 44 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    throw const FormatException('Not a WAV file');
  }
  int? rate, channels, bits, format;
  var pos = 12;
  while (pos + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
    final size = d.getUint32(pos + 4, Endian.little);
    final body = pos + 8;
    if (id == 'fmt ') {
      format = d.getUint16(body, Endian.little);
      channels = d.getUint16(body + 2, Endian.little);
      rate = d.getUint32(body + 4, Endian.little);
      bits = d.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      if (format != 1 ||
          bits != 16 ||
          rate == null ||
          channels == null ||
          channels < 1) {
        throw FormatException('Unsupported WAV (format $format, $bits bits)');
      }
      final available = bytes.length - body;
      // Streamed files may announce a size of 0 or 0xFFFFFFFF.
      final length =
          (size == 0 || size > available ? available : size) ~/ (2 * channels);
      final out = Float32List(length);
      for (var i = 0; i < length; i++) {
        var sum = 0;
        for (var c = 0; c < channels; c++) {
          sum += d.getInt16(body + (i * channels + c) * 2, Endian.little);
        }
        out[i] = sum / channels / 32768.0;
      }
      return Pcm(out, rate);
    }
    pos = body + size + (size.isOdd ? 1 : 0);
  }
  throw const FormatException('WAV file has no data');
}

Pcm readWavFile(File file) => readWavPcm16(file.readAsBytesSync());

/// Linear-interpolation resampling to [rate] (speech recognisers are not
/// sensitive to the quality of this).
Float32List resample(Float32List samples, int from, int to) {
  if (from == to || samples.isEmpty) return samples;
  final n = (samples.length * to / from).floor();
  final out = Float32List(n);
  final step = from / to;
  for (var i = 0; i < n; i++) {
    final x = i * step;
    final i0 = x.floor();
    final i1 = i0 + 1 < samples.length ? i0 + 1 : i0;
    final f = x - i0;
    out[i] = samples[i0] * (1 - f) + samples[i1] * f;
  }
  return out;
}
