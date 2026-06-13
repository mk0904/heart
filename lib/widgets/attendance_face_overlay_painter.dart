import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class AttendanceFaceOverlayPainter extends CustomPainter {
  AttendanceFaceOverlayPainter({
    required this.face,
    required this.imageSize,
    required this.previewSize,
    required this.isFrontCamera,
  });

  final Face face;
  final Size imageSize;
  final Size previewSize;
  final bool isFrontCamera;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.greenAccent;

    final scaleX = previewSize.width / imageSize.width;
    final scaleY = previewSize.height / imageSize.height;
    final rect = face.boundingBox;

    final left = isFrontCamera
        ? previewSize.width - (rect.right * scaleX)
        : rect.left * scaleX;
    final right = isFrontCamera
        ? previewSize.width - (rect.left * scaleX)
        : rect.right * scaleX;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(left, rect.top * scaleY, right, rect.bottom * scaleY),
        const Radius.circular(18),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant AttendanceFaceOverlayPainter oldDelegate) {
    return oldDelegate.face != face ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.previewSize != previewSize ||
        oldDelegate.isFrontCamera != isFrontCamera;
  }
}
