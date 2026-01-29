import 'dart:io';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:image/image.dart' as img;

class FaceDetectionService {
  final FaceDetector faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: false,
      enableLandmarks: false,
      enableTracking: false,
      minFaceSize: 0.1,
    ),
  );

  Future<Face?> detectFace(InputImage inputImage) async {
    try {
      final faces = await faceDetector.processImage(inputImage);
      if (faces.isNotEmpty) {
        return faces.first;
      }
      return null;
    } catch (e) {
      print('Face detection error: $e');
      return null;
    }
  }

  Future<img.Image?> cropFace(img.Image image, Face face) async {
    try {
      final rect = face.boundingBox;
      final imageWidth = image.width;
      final imageHeight = image.height;
      
      // Ensure coordinates are within image bounds
      final x = rect.left.toInt().clamp(0, imageWidth);
      final y = rect.top.toInt().clamp(0, imageHeight);
      final width = rect.width.toInt().clamp(0, imageWidth - x);
      final height = rect.height.toInt().clamp(0, imageHeight - y);
      
      final cropped = img.copyCrop(
        image,
        x: x,
        y: y,
        width: width,
        height: height,
      );
      return cropped;
    } catch (e) {
      print('Face cropping error: $e');
      return null;
    }
  }

  void dispose() {
    faceDetector.close();
  }
}
