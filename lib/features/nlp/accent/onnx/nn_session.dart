import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// Flat logits of one inference call.
class Logits {
  const Logits(this.data, this.shape);

  final List<double> data;
  final List<int> shape;

  int get classes => shape.last;

  /// Row [i] of the last dimension, flattened over leading dimensions.
  List<double> row(int i) => data.sublist(i * classes, (i + 1) * classes);
  int get rows => data.length ~/ classes;
}

/// One loaded ONNX transformer-classifier (batch size 1).
abstract class NnSession {
  Future<Logits> run(List<int> inputIds, {List<int>? tokenTypeIds});
  Future<void> close();
}

/// [NnSession] backed by the flutter_onnxruntime plugin. Supplies exactly the
/// inputs the model declares (input_ids, attention_mask, token_type_ids).
class OrtNnSession implements NnSession {
  OrtNnSession._(this._session);

  final OrtSession _session;

  static Future<OrtNnSession> open(String modelPath) async =>
      OrtNnSession._(await OnnxRuntime().createSession(modelPath));

  @override
  Future<Logits> run(List<int> inputIds, {List<int>? tokenTypeIds}) async {
    final n = inputIds.length;
    final tensors = <String, OrtValue>{};
    try {
      for (final name in _session.inputNames) {
        final List<int> values = switch (name) {
          'input_ids' => inputIds,
          'attention_mask' => List.filled(n, 1),
          'token_type_ids' => tokenTypeIds ?? List.filled(n, 0),
          _ => throw StateError('Unsupported model input: $name'),
        };
        tensors[name] = await OrtValue.fromList(Int64List.fromList(values), [1, n]);
      }
      final outputs = await _session.run(tensors);
      final out = outputs['logits'] ?? outputs.values.first;
      try {
        final flat = await out.asFlattenedList();
        return Logits([for (final v in flat) (v as num).toDouble()], out.shape);
      } finally {
        for (final o in outputs.values) {
          await o.dispose();
        }
      }
    } finally {
      for (final t in tensors.values) {
        await t.dispose();
      }
    }
  }

  @override
  Future<void> close() => _session.close();
}
