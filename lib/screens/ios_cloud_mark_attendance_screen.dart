import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import '../services/face_detection_service.dart';
import '../services/attendance_service.dart';
import '../services/firebase_auth_service.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';
import '../widgets/attendance_face_overlay_painter.dart';

/// iOS (or non-Android) face registration without TFLite: ML Kit crop + photo upload + optional empty embedding.
/// Enable with `--dart-define=IOS_CLOUD_ATTENDANCE=true` and use [AttendanceScreen] routing.
class IosCloudRegisterFaceScreen extends StatefulWidget {
  const IosCloudRegisterFaceScreen({super.key});

  @override
  State<IosCloudRegisterFaceScreen> createState() => _IosCloudRegisterFaceScreenState();
}

class _IosCloudRegisterFaceScreenState extends State<IosCloudRegisterFaceScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  int _cameraIndex = 0;
  bool _isInitialized = false;
  bool _isProcessing = false;
  final FaceDetectionService _faceDetectionService = FaceDetectionService();
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
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _attendanceService.ensureInitialized();
    if (!mounted) return;
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
      // Check camera permission
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Camera permission is required for registration'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.pop(context);
        }
        return;
      }

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
      enableAudio: false, // Ensure audio is disabled to prevent mic permission issues
      imageFormatGroup: Platform.isAndroid 
          ? ImageFormatGroup.nv21 
          : ImageFormatGroup.bgra8888,
    );

    try {
      await _controller!.initialize();
      if (mounted) {
        setState(() {
          _cameraIndex = cameraIndex;
          _isInitialized = true;
        });
        // Start live face detection
        _startLiveFeed();
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

  void _startLiveFeed() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isDetecting) return;

    try {
      await _controller?.startImageStream((CameraImage image) async {
        if (_isDetecting || _isProcessing) return;

        _isDetecting = true;
        try {
          final inputImage = _inputImageFromCameraImage(image);
          if (inputImage == null) return;

          final faces = await _faceDetector.processImage(inputImage);
          
          if (mounted) {
            setState(() {
              _detectedFace = faces.isNotEmpty ? faces.first : null;
            });
          }
        } catch (e) {
          print('Face detection error: $e');
        } finally {
          _isDetecting = false;
        }
      });
    } catch (e) {
      print('Error starting image stream: $e');
    }
  }

  Future<void> _stopLiveFeed() async {
    if (_controller != null && _controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null) return null;

    final camera = _cameras![_cameraIndex];
    final sensorOrientation = camera.sensorOrientation;
    
    // On iOS, the image orientation is different
    // We need to properly calculate the rotation based on device orientation and camera sensor
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = _orientations[_controller!.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        // front-facing
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        // back-facing
        rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    
    // iOS often uses bgra8888, Android often uses yuv420
    // Validate that format is supported
    if (format == null || 
        (Platform.isAndroid && format != InputImageFormat.nv21 && format != InputImageFormat.yv12) || 
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
          // If format is not standard, we might need more complex conversion or just skip
          // However, for basic cases:
          if (format == null) return null;
    }

    // Since we're just doing detection, we can pass the bytes directly
    // Note: This requires the latest google_mlkit_commons
    
    // For simplicity in this fix, we'll try the standard plane concatenation
    // InputImagePlaneMetadata removed as it's not needed/supported in this version

    return InputImage.fromBytes(
      bytes: _concatenatePlanes(image.planes),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  static final Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  Future<void> _toggleCamera() async {
    if (_cameras == null || _cameras!.length < 2) {
      return;
    }
    await _stopLiveFeed(); // Stop feed before switching
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

    // Pause live feed during processing
    await _stopLiveFeed();

    try {
      final image = await _controller!.takePicture();
      final imageFile = File(image.path);
      final imageBytes = await imageFile.readAsBytes();
      
      // Decode image to handle orientation/EXIF automatically
      final decodedImage = img.decodeImage(imageBytes);

      if (decodedImage == null) {
        throw Exception('Failed to decode image');
      }

      // Save the normalized (rotated) image to a temp file for consistent detection
      // This strips strict EXIF rotation tags that might confuse ML Kit on iOS
      final tempDir = Directory.systemTemp;
      final fixedPath = '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_fixed.jpg';
      final fixedFile = File(fixedPath);
      await fixedFile.writeAsBytes(img.encodeJpg(decodedImage));

      // Convert to InputImage using the fixed file
      final inputImage = InputImage.fromFilePath(fixedPath);
      final face = await _faceDetectionService.detectFace(inputImage);

      if (face == null) {
        // Clean up temp file
        if (await fixedFile.exists()) await fixedFile.delete();
        throw Exception('No face detected. Please ensure your face is clearly visible.');
      }

      // Crop face (using the same decodedImage which matches the fixed file pixels)
      final croppedFace = await _faceDetectionService.cropFace(decodedImage, face);
      
      // Clean up temp file
      if (await fixedFile.exists()) await fixedFile.delete();

      if (croppedFace == null) {
        throw Exception('Failed to crop face');
      }

      final regFaceFile = File(
        '${Directory.systemTemp.path}/face_reg_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await regFaceFile.writeAsBytes(img.encodeJpg(croppedFace, quality: 90));
      try {
        await _attendanceService.registerPersonWithFirebase(
          name: _userName!,
          employeeId: _userUid!,
          faceEmbedding: null,
          faceImageFile: regFaceFile,
        );
      } finally {
        if (await regFaceFile.exists()) await regFaceFile.delete();
      }

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
      print('Registration error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
        // Restart live feed on error
        _startLiveFeed();
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
    _stopLiveFeed();
    _controller?.dispose();
    _faceDetectionService.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Register face'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isInitialized && _controller != null
          ? Stack(
              children: [
                // Camera Preview (Full Screen)
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.biggest;
                      var scale = size.aspectRatio * _controller!.value.aspectRatio;

                      // to prevent scaling down, invert the value
                      if (scale < 1) scale = 1 / scale;

                      return Transform.scale(
                        scale: scale,
                        child: Center(
                          child: CameraPreview(
                            _controller!,
                            child: _detectedFace != null
                                ? LayoutBuilder(
                                    builder: (context, constraints) {
                                      final previewSize = _controller!.value.previewSize;
                                      if (previewSize == null) return const SizedBox();
                                      
                                      return CustomPaint(
                                        painter: AttendanceFaceOverlayPainter(
                                          face: _detectedFace!,
                                          imageSize: Size(previewSize.height, previewSize.width),
                                          previewSize: constraints.biggest,
                                          isFrontCamera: _cameras?[_cameraIndex].lensDirection == CameraLensDirection.front,
                                        ),
                                      );
                                    },
                                  )
                                : null,
                          ),
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
