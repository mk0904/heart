import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import '../services/face_detection_service.dart';
import '../services/face_recognition_service.dart';
import '../services/attendance_service.dart';
import '../theme/app_theme.dart';

class MarkAttendanceScreen extends StatefulWidget {
  final bool isCheckIn;
  
  const MarkAttendanceScreen({super.key, required this.isCheckIn});

  @override
  State<MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends State<MarkAttendanceScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  int _cameraIndex = 0;
  bool _isInitialized = false;
  bool _isProcessing = false;
  final bool _requestingPermission = false;
  // bool _verifyingLocation = true; // Removed blocking state
  
  // Liveness check state
  bool _livenessVerified = false;
  String _feedbackText = "Position your face in the circle";
  bool _isBlinking = false;
  int _blinkCount = 0;
  bool _canProcessStream = true;
  DateTime? _lastProcessTime;
  
  final FaceDetectionService _faceDetectionService = FaceDetectionService();
  final FaceRecognitionService _faceRecognitionService = FaceRecognitionService();
  final AttendanceService _attendanceService = AttendanceService();

  @override
  void initState() {
    super.initState();
    // Run final verification in background without blocking camera
    _finalVerification();
    _initializeCamera();
  }

  Future<void> _finalVerification() async {
    // 1. Check Time (Silent check)
    bool isTimeValid;
    String timeErrorMsg;

    if (widget.isCheckIn) {
       isTimeValid = await _attendanceService.isCheckInAllowed();
       timeErrorMsg = "Check-in allowed only before college start time";
    } else {
       isTimeValid = await _attendanceService.isCheckOutAllowed();
       timeErrorMsg = "Check-out allowed only after college hours";
    }

    if (!mounted) return;
    
    if (!isTimeValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(timeErrorMsg),
          backgroundColor: Colors.orange,
        ),
      );
      Navigator.pop(context);
      return;
    }

    // 2. Check Geofence (Silent check)
    final geofenceResult = await _attendanceService.validateGeofence();
    if (!mounted) return;

    if (!geofenceResult['valid']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(geofenceResult['message'] ?? 'You have moved out of the allowed area'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
      Navigator.pop(context);
      return;
    }
    
    // If valid, just continue. No state update needed since we aren't blocking.
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _switchCamera(int cameraIndex) async {
    if (_cameras == null || cameraIndex >= _cameras!.length) {
      return;
    }

    await _controller?.dispose();

    // Use lower resolution for stream processing to be faster
    _controller = CameraController(
      _cameras![cameraIndex],
      ResolutionPreset.medium,
      enableAudio: false,
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
        _startImageStream();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }

  void _startImageStream() {
    if (_controller == null) return;
    
    _controller!.startImageStream((CameraImage image) {
      if (_isProcessing || _livenessVerified || !_canProcessStream) return;
      
      // Throttle processing to ~5fps to save battery and CPU
      final now = DateTime.now();
      if (_lastProcessTime != null && 
          now.difference(_lastProcessTime!).inMilliseconds < 200) {
        return;
      }
      _lastProcessTime = now;

      _processCameraImage(image);
    });
  }

  Future<void> _processCameraImage(CameraImage image) async {
    _canProcessStream = false;
    
    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) {
        _canProcessStream = true;
        return;
      }
      
      final faces = await _faceDetectionService.faceDetector.processImage(inputImage);
      
      if (mounted) {
        if (faces.isEmpty) {
          setState(() {
            _feedbackText = "No face detected";
            _isBlinking = false;
          });
        } else if (faces.length > 1) {
           setState(() {
            _feedbackText = "Multiple faces detected";
             _isBlinking = false;
          });
        } else {
          final face = faces.first;
          _checkLiveness(face);
        }
      }
    } catch (e) {
      // print("Error processing stream: $e");
    } finally {
      if (mounted) {
         _canProcessStream = true; 
      }
    }
  }

  void _checkLiveness(Face face) {
    // Face is detected
    final leftOpen = face.leftEyeOpenProbability;
    final rightOpen = face.rightEyeOpenProbability;
    
    if (leftOpen == null || rightOpen == null) {
      setState(() {
        _feedbackText = "Keep face steady";
      });
      return;
    }

    final isEyesClosed = leftOpen < 0.35 && rightOpen < 0.35;
    final isEyesOpen = leftOpen > 0.85 && rightOpen > 0.85;

    if (_livenessVerified) return;

    if (isEyesOpen) {
      if (_isBlinking) {
        // Was blinking, now open -> Blink completed!
        _blinkCount++;
        setState(() {
          _isBlinking = false;
          if (_blinkCount >= 1) {
             _livenessVerified = true;
             _feedbackText = "Verified! Marking attendance...";
             // Auto-capture after verification
             _stopStreamAndCapture();
          } else {
            _feedbackText = "Blink detected. Do it once more.";
          }
        });
      } else {
         setState(() {
          _feedbackText = "Please blink to verify you are human";
        });
      }
    } else if (isEyesClosed) {
      setState(() {
        _isBlinking = true;
        _feedbackText = "Eyes closed...";
      });
    } else {
       setState(() {
        _feedbackText = "Please blink clearly";
      });
    }
  }

  Future<void> _stopStreamAndCapture() async {
    await _controller?.stopImageStream();
    
    // Slight delay to allow user to open eyes fully and stabilize
    await Future.delayed(const Duration(milliseconds: 500));
    
    _captureAndMarkAttendance();
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null) return null;

    final camera = _cameras![_cameraIndex];
    final sensorOrientation = camera.sensorOrientation;
    
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

    InputImageFormat? format;
    if (Platform.isIOS) {
      if (image.format.group == ImageFormatGroup.bgra8888) {
        format = InputImageFormat.bgra8888;
      }
    } else if (Platform.isAndroid) {
      if (image.format.group == ImageFormatGroup.nv21) {
        format = InputImageFormat.nv21;
      } else if (image.format.group == ImageFormatGroup.yuv420) {
        format = InputImageFormat.nv21; // camera package often uses yuv420 for nv21-like data
      }
    }
    
    if (format == null) return null;

    // Basic construction for NV21 (Android) and BGRA8888 (iOS)
    if (image.planes.isEmpty) return null;
    
    // Calculate total bytes
    final bytes = WriteBuffer();
    for (final plane in image.planes) {
      bytes.putUint8List(plane.bytes);
    }
    final allBytes = bytes.done().buffer.asUint8List();
    
    return InputImage.fromBytes(
       bytes: allBytes,
       metadata: InputImageMetadata(
         size: Size(image.width.toDouble(), image.height.toDouble()),
         rotation: rotation,
         format: format,
         bytesPerRow: image.planes[0].bytesPerRow,
       ),
    );
  }
  
  final _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  Future<void> _captureAndMarkAttendance() async {
    if (_controller == null || _isProcessing) return;

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

      final tempDir = Directory.systemTemp;
      final fixedPath = '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_attendance_fixed.jpg';
      final fixedFile = File(fixedPath);
      await fixedFile.writeAsBytes(img.encodeJpg(decodedImage));

      final inputImage = InputImage.fromFilePath(fixedPath);
      final face = await _faceDetectionService.detectFace(inputImage);

      if (await fixedFile.exists()) await fixedFile.delete();

      if (face == null) {
        // If liveness was verified but final capture failed to find face (motion blur etc)
        // We might want to retry or ask user to try again
        throw Exception('Face detection failed on capture. Please try again.');
      }

      final croppedFace = await _faceDetectionService.cropFace(decodedImage, face);
      if (croppedFace == null) {
        throw Exception('Failed to crop face');
      }

      final embedding = await _faceRecognitionService.getFaceEmbedding(croppedFace);
      final person = await _attendanceService.recognizePerson(embedding);

      if (person == null) {
        throw Exception('Person not recognized using face. Please register first.');
      }

      final confidence = _faceRecognitionService.cosineSimilarity(
        embedding,
        person.faceEmbedding,
      );

      bool isTimeValid;
      if (widget.isCheckIn) {
        isTimeValid = await _attendanceService.isCheckInAllowed();
      } else {
        isTimeValid = await _attendanceService.isCheckOutAllowed();
      }
      
      if (!isTimeValid) {
        throw Exception(widget.isCheckIn 
          ? 'Check-in allowed only before college start time' 
          : 'Check-out allowed only after college hours');
      }

      final geofenceResult = await _attendanceService.validateGeofence();
      if (!geofenceResult['valid'] && geofenceResult['message'] != 'College details not found') {
        if (geofenceResult['message']?.contains('km away') ?? false) {
          throw Exception(geofenceResult['message'] ?? 'Location validation failed');
        }
      }

      await _attendanceService.markAttendance(
        person: person,
        type: widget.isCheckIn ? 'check_in' : 'check_out',
        confidence: confidence,
      );

      if (mounted) {
        Navigator.pop(context);
        
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${widget.isCheckIn ? 'Check-in' : 'Check-out'} marked for ${person.name}!',
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        // Reset state to allow retry
        setState(() {
          _isProcessing = false;
          _livenessVerified = false;
          _blinkCount = 0;
          _feedbackText = "Please try again";
        });
        // Restart stream for retry
        _startImageStream();
        
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Failed'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetectionService.dispose();
    _faceRecognitionService.dispose();
    _livenessVerified = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_requestingPermission) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: _isInitialized && _controller != null
          ? Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.biggest;
                      var scale = size.aspectRatio * _controller!.value.aspectRatio;
                      if (scale < 1) scale = 1 / scale;
                      return Transform.scale(
                        scale: scale,
                        child: Center(
                          child: CameraPreview(_controller!),
                        ),
                      );
                    },
                  ),
                ),
                
                // Liveness Overlay
                Center(
                  child: Container(
                    width: 250,
                    height: 320,
                    decoration: BoxDecoration(
                      shape: BoxShape.rectangle,
                      borderRadius: BorderRadius.circular(125),
                      border: Border.all(
                        color: _livenessVerified 
                            ? Colors.green 
                            : (_isBlinking ? Colors.blue : Colors.white.withValues(alpha: 0.5)),
                        width: 3,
                      ),
                    ),
                  ),
                ),

                // Liveness Instructions
                Positioned(
                  bottom: 220,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                       AnimatedOpacity(
                         opacity: _isProcessing ? 0.0 : 1.0,
                         duration: const Duration(milliseconds: 300),
                         child: Container(
                           padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                           decoration: BoxDecoration(
                             color: Colors.black54,
                             borderRadius: BorderRadius.circular(30),
                           ),
                           child: Text(
                             _feedbackText,
                             style: TextStyle(
                               fontSize: 18,
                               fontWeight: FontWeight.bold,
                               color: _livenessVerified ? Colors.greenAccent : Colors.white,
                             ),
                             textAlign: TextAlign.center,
                           ),
                         ),
                       ),
                    ],
                  ),
                ),
                
                // Processing Indicator
                if (_isProcessing)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: AppTheme.primary),
                          SizedBox(height: 20),
                          Text("Marking attendance...", style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  ),

                // Location Verification Indicator - REMOVED
                // We now check silently in background to allow instant camera access

                // Cancel Button Only (Capture is automatic now)
                if (!_isProcessing)
                Positioned(
                  bottom: 50,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppTheme.spacingSM,
                          horizontal: AppTheme.spacing2XL,
                        ),
                        backgroundColor: Colors.black.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
    );
  }
}
