import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import '../services/face_detection_service.dart';
import '../services/face_recognition_service.dart';
import '../services/attendance_service.dart';
import '../services/firebase_auth_service.dart';
import '../theme/app_theme.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  int _cameraIndex = 0;
  bool _isInitialized = false;
  bool _isProcessing = false;
  final FaceDetectionService _faceDetectionService = FaceDetectionService();
  final FaceRecognitionService _faceRecognitionService = FaceRecognitionService();
  final AttendanceService _attendanceService = AttendanceService();
  final FirebaseAuthService _authService = FirebaseAuthService();
  
  // Real-time face detection
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: false,
      enableLandmarks: false,
      enableTracking: false,
      minFaceSize: 0.1,
    ),
  );
  Face? _detectedFace;
  bool _isDetecting = false;
  String? _userName;
  String? _userUid;

  @override
  void initState() {
    super.initState();
    _loadUserDetails();
    _initializeCamera();
  }

  Future<void> _loadUserDetails() async {
    try {
      final user = await _authService.getCurrentUser();
      if (user != null && mounted) {
        setState(() {
          _userName = user.name ?? 'User';
          _userUid = user.uid;
        });
      }
    } catch (e) {
      // Ignore error
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        // Find front camera index (default to front camera)
        int frontCameraIndex = 0;
        for (int i = 0; i < _cameras!.length; i++) {
          if (_cameras![i].lensDirection == CameraLensDirection.front) {
            frontCameraIndex = i;
            break;
          }
        }
        _cameraIndex = frontCameraIndex;
        await _switchCamera(frontCameraIndex);
      }
    } catch (e) {
      print('Error initializing camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }

  Future<void> _switchCamera(int cameraIndex) async {
    if (_cameras == null || cameraIndex >= _cameras!.length) {
      return;
    }

    // Dispose the old controller
    await _controller?.dispose();

    // Initialize new controller
    _controller = CameraController(
      _cameras![cameraIndex],
      ResolutionPreset.medium,
    );

      try {
        await _controller!.initialize();
        if (mounted) {
          setState(() {
            _cameraIndex = cameraIndex;
            _isInitialized = true;
          });
          // Start periodic face detection
          _startPeriodicFaceDetection();
        }
      } catch (e) {
      print('Error switching camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }

  void _startPeriodicFaceDetection() {
    // Detect faces every 1.5 seconds to avoid too frequent captures
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && _controller != null && _controller!.value.isInitialized && !_isProcessing) {
        _detectFaceInPreview();
        _startPeriodicFaceDetection(); // Continue detecting
      }
    });
  }

  Future<void> _detectFaceInPreview() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isDetecting || _isProcessing) return;
    
    _isDetecting = true;
    try {
      // Take a temporary picture for detection
      final image = await _controller!.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      final faces = await _faceDetector.processImage(inputImage);
      
      if (mounted) {
        setState(() {
          _detectedFace = faces.isNotEmpty ? faces.first : null;
        });
      }
      
      // Delete temporary file
      try {
        await File(image.path).delete();
      } catch (e) {
        // Ignore deletion errors
      }
    } catch (e) {
      print('Face detection error: $e');
      if (mounted) {
        setState(() {
          _detectedFace = null;
        });
      }
    } finally {
      _isDetecting = false;
    }
  }

  Future<void> _toggleCamera() async {
    if (_cameras == null || _cameras!.length < 2) {
      return;
    }
    // Switch to the other camera
    final newIndex = _cameraIndex == 0 ? 1 : 0;
    await _switchCamera(newIndex);
  }

  Future<void> _captureAndRegister() async {
    if (_userName == null || _userUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User details not available. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_detectedFace == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please position your face in the frame'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final image = await _controller!.takePicture();
      final imageFile = File(image.path);
      final imageBytes = await imageFile.readAsBytes();
      final decodedImage = img.decodeImage(imageBytes);

      if (decodedImage == null) {
        throw Exception('Failed to decode image');
      }

      // Convert to InputImage for face detection
      final inputImage = InputImage.fromFilePath(image.path);
      final face = await _faceDetectionService.detectFace(inputImage);

      if (face == null) {
        throw Exception('No face detected. Please ensure your face is clearly visible.');
      }

      // Crop face
      final croppedFace = await _faceDetectionService.cropFace(decodedImage, face);
      if (croppedFace == null) {
        throw Exception('Failed to crop face');
      }

      // Get face embedding
      final embedding = await _faceRecognitionService.getFaceEmbedding(croppedFace);

      // Register person with Firebase user details
      await _attendanceService.registerPersonWithFirebase(
        name: _userName!,
        employeeId: _userUid!,
        faceEmbedding: embedding,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Face registered successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
        // Restart periodic face detection
        _startPeriodicFaceDetection();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetectionService.dispose();
    _faceRecognitionService.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Register Face'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isInitialized
          ? Stack(
              children: [
                // Camera Preview
                Positioned.fill(
                  child: CameraPreview(_controller!),
                ),
                
                // Face Detection Overlay
                if (_detectedFace != null && _controller != null)
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final previewSize = _controller!.value.previewSize;
                        if (previewSize == null) return const SizedBox();
                        
                        return CustomPaint(
                          painter: FaceDetectionPainter(
                            face: _detectedFace!,
                            imageSize: Size(previewSize.height, previewSize.width),
                            previewSize: constraints.biggest,
                            isFrontCamera: _cameras?[_cameraIndex].lensDirection == CameraLensDirection.front,
                          ),
                        );
                      },
                    ),
                  ),
                
                // Processing Overlay
                if (_isProcessing)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: Colors.white,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Processing...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                
                // Instructions
                if (!_isProcessing)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _detectedFace != null
                            ? 'Face detected! Tap capture to register.'
                            : 'Position your face in the frame',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                
                // Camera switch button
                if (_cameras != null && _cameras!.length > 1 && !_isProcessing)
                  Positioned(
                    top: 80,
                    right: 16,
                    child: FloatingActionButton(
                      mini: true,
                      onPressed: _toggleCamera,
                      backgroundColor: Colors.black54,
                      child: const Icon(Icons.cameraswitch, color: Colors.white),
                    ),
                  ),
                
                // Capture button
                if (!_isProcessing)
                  Positioned(
                    bottom: 40,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: FloatingActionButton(
                        onPressed: _detectedFace != null ? _captureAndRegister : null,
                        backgroundColor: _detectedFace != null ? AppTheme.primary : Colors.grey,
                        child: const Icon(Icons.camera_alt, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            )
          : const Center(
              child: CircularProgressIndicator(),
            ),
    );
  }
}

// Custom painter for face detection bounding box
class FaceDetectionPainter extends CustomPainter {
  final Face face;
  final Size imageSize;
  final Size previewSize;
  final bool isFrontCamera;

  FaceDetectionPainter({
    required this.face,
    required this.imageSize,
    required this.previewSize,
    required this.isFrontCamera,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // Get bounding box
    final rect = face.boundingBox;
    
    // Calculate scale factors - account for aspect ratio
    final imageAspectRatio = imageSize.width / imageSize.height;
    final previewAspectRatio = previewSize.width / previewSize.height;
    
    double scaleX, scaleY, offsetX = 0, offsetY = 0;
    
    if (imageAspectRatio > previewAspectRatio) {
      // Image is wider - fit to width
      scaleX = previewSize.width / imageSize.width;
      scaleY = scaleX;
      offsetY = (previewSize.height - imageSize.height * scaleY) / 2;
    } else {
      // Image is taller - fit to height
      scaleY = previewSize.height / imageSize.height;
      scaleX = scaleY;
      offsetX = (previewSize.width - imageSize.width * scaleX) / 2;
    }
    
    // Adjust coordinates based on camera orientation
    double left, top, width, height;
    if (isFrontCamera) {
      // Front camera is mirrored, so flip horizontally
      left = (imageSize.width - rect.right) * scaleX + offsetX;
      top = rect.top * scaleY + offsetY;
      width = rect.width * scaleX;
      height = rect.height * scaleY;
    } else {
      left = rect.left * scaleX + offsetX;
      top = rect.top * scaleY + offsetY;
      width = rect.width * scaleX;
      height = rect.height * scaleY;
    }

    // Draw bounding box
    canvas.drawRect(
      Rect.fromLTWH(left, top, width, height),
      paint,
    );

    // Draw corner indicators
    final cornerPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.fill;

    final cornerSize = 20.0;
    
    // Top-left corner
    canvas.drawRect(
      Rect.fromLTWH(left, top, cornerSize, 3),
      cornerPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(left, top, 3, cornerSize),
      cornerPaint,
    );
    
    // Top-right corner
    canvas.drawRect(
      Rect.fromLTWH(left + width - cornerSize, top, cornerSize, 3),
      cornerPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(left + width - 3, top, 3, cornerSize),
      cornerPaint,
    );
    
    // Bottom-left corner
    canvas.drawRect(
      Rect.fromLTWH(left, top + height - 3, cornerSize, 3),
      cornerPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(left, top + height - cornerSize, 3, cornerSize),
      cornerPaint,
    );
    
    // Bottom-right corner
    canvas.drawRect(
      Rect.fromLTWH(left + width - cornerSize, top + height - 3, cornerSize, 3),
      cornerPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(left + width - 3, top + height - cornerSize, 3, cornerSize),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(FaceDetectionPainter oldDelegate) {
    return oldDelegate.face != face;
  }
}
