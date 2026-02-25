import 'dart:math' as math;

class FaceRecognitionService {
  // Model logic moved to web app.
  // Kept here for potential local math usage or legacy references.

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
}
