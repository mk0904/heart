import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Legacy on-device face recognition facade.
///
/// The app now uses [CloudFaceService] for registration and attendance matching,
/// so this class stays only to keep older Android-only screens compiling while
/// the cloud flow is enabled by default.
class FaceRecognitionService {
  static const int inputSize = 112;
  static const int embeddingSize = 192;

  Future<void> loadModel() async {
    throw UnsupportedError(
      'On-device TFLite face recognition has been replaced by cloud matching.',
    );
  }

  Future<List<double>> getFaceEmbedding(img.Image faceImage) async {
    throw UnsupportedError(
      'On-device TFLite face recognition has been replaced by cloud matching.',
    );
  }

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

  void dispose() {}
}
