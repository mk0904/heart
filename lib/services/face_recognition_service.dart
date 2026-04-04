import 'dart:io' show File, Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class FaceRecognitionService {
  Interpreter? _interpreter;
  static const MethodChannel _modelChannel =
      MethodChannel('com.mk2004.heartnagaland/tflite_model');

  static const int inputSize = 112; // MobileFaceNet input size
  static const int embeddingSize = 192; // MobileFaceNet output size

  /// Loads [mobilefacenet.tflite] from Android native assets only (not in iOS IPA).
  Future<void> loadModel() async {
    if (kIsWeb || !Platform.isAndroid) {
      throw UnsupportedError('Face recognition model is only used on Android');
    }
    if (_interpreter != null) return;
    try {
      final path = await _modelChannel.invokeMethod<String>('getMobileFaceNetPath');
      if (path == null || path.isEmpty) {
        throw StateError('TFLite model path not provided');
      }
      _interpreter = Interpreter.fromFile(File(path));
    } catch (e) {
      debugPrint('Error loading model: $e');
      rethrow;
    }
  }

  Future<List<double>> getFaceEmbedding(img.Image faceImage) async {
    if (_interpreter == null) {
      await loadModel();
    }

    try {
      // Resize to 112x112 (MobileFaceNet input size)
      final resized = img.copyResize(
        faceImage,
        width: inputSize,
        height: inputSize,
      );

      // Convert to float32 array and normalize
      final input = _imageToFloatList(resized);

      // Prepare output buffer - TensorFlow Lite expects List<List<double>>
      final output = [List.filled(embeddingSize, 0.0)];

      // Run inference
      _interpreter!.run(input, output);

      // Normalize the embedding (L2 normalization)
      return _normalize(output[0]);
    } catch (e) {
      debugPrint('Error getting face embedding: $e');
      rethrow;
    }
  }

  List<List<List<List<double>>>> _imageToFloatList(img.Image image) {
    // Create 4D tensor: [1, height, width, channels]
    final result = <List<List<List<double>>>>[];
    final batch = <List<List<double>>>[];

    for (int i = 0; i < inputSize; i++) {
      final row = <List<double>>[];
      for (int j = 0; j < inputSize; j++) {
        final pixel = image.getPixel(j, i);
        // Normalize pixel values to [-1, 1] range
        // In image v4, access pixel channels directly via properties
        final r = (pixel.r.toDouble() / 127.5) - 1.0;
        final g = (pixel.g.toDouble() / 127.5) - 1.0;
        final b = (pixel.b.toDouble() / 127.5) - 1.0;
        final channels = <double>[r, g, b];
        row.add(channels);
      }
      batch.add(row);
    }
    result.add(batch);
    return result;
  }

  List<double> _normalize(List<double> vector) {
    double sum = 0.0;
    for (var value in vector) {
      sum += value * value;
    }
    final norm = 1.0 / (math.sqrt(sum) + 1e-10);
    return vector.map((v) => v * norm).toList();
  }

  // Calculate Euclidean distance (lower is more similar)
  double euclideanDistance(List<double> emb1, List<double> emb2) {
    if (emb1.length != emb2.length) {
      throw Exception('Embeddings must have the same length');
    }
    double sum = 0.0;
    for (int i = 0; i < emb1.length; i++) {
      final diff = emb1[i] - emb2[i];
      sum += diff * diff;
    }
    return math.sqrt(sum);
  }

  // Calculate cosine similarity (higher is more similar, range: -1 to 1)
  double cosineSimilarity(List<double> emb1, List<double> emb2) {
    if (emb1.length != emb2.length) {
      throw Exception('Embeddings must have the same length');
    }
    double dotProduct = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;

    for (int i = 0; i < emb1.length; i++) {
      dotProduct += emb1[i] * emb2[i];
      norm1 += emb1[i] * emb1[i];
      norm2 += emb2[i] * emb2[i];
    }

    return dotProduct / (math.sqrt(norm1) * math.sqrt(norm2) + 1e-10);
  }

  void dispose() {
    _interpreter?.close();
  }
}
