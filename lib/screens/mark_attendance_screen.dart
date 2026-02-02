import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
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
  bool _requestingPermission = false;
  final FaceDetectionService _faceDetectionService = FaceDetectionService();
  final FaceRecognitionService _faceRecognitionService = FaceRecognitionService();
  final AttendanceService _attendanceService = AttendanceService();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
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
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }

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

      final inputImage = InputImage.fromFilePath(image.path);
      final face = await _faceDetectionService.detectFace(inputImage);

      if (face == null) {
        throw Exception('No face detected. Please ensure your face is clearly visible.');
      }

      final croppedFace = await _faceDetectionService.cropFace(decodedImage, face);
      if (croppedFace == null) {
        throw Exception('Failed to crop face');
      }

      final embedding = await _faceRecognitionService.getFaceEmbedding(croppedFace);
      final person = await _attendanceService.recognizePerson(embedding);

      if (person == null) {
        throw Exception('Person not recognized. Please register first.');
      }

      // Calculate confidence (using cosine similarity)
      final confidence = _faceRecognitionService.cosineSimilarity(
        embedding,
        person.faceEmbedding,
      );

      // Check time validation
      final isWithinHours = await _attendanceService.isWithinCollegeHours();
      if (!isWithinHours) {
        throw Exception('Attendance can only be marked during college hours');
      }

      // Check geofence validation (skip if offline)
      final geofenceResult = await _attendanceService.validateGeofence();
      if (!geofenceResult['valid'] && geofenceResult['message'] != 'College details not found') {
        // Only fail if it's a real geofence issue, not just missing college details
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
        // Always navigate back, even if sync failed (it will sync later)
        Navigator.pop(context);
        
        // Show success message after navigation
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
        setState(() {
          _isProcessing = false;
        });
        
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
                child: const Text('Try Again'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Go back to attendance screen
                },
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      }
    } finally {
      // Ensure processing flag is reset
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_requestingPermission) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppTheme.primary),
              SizedBox(height: AppTheme.spacingLG),
              Text(
                'Requesting camera permission...',
                style: TextStyle(color: AppTheme.text),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: _isInitialized && _controller != null
          ? Stack(
              children: [
                // Camera Preview (preserve aspect ratio to avoid horizontal squeeze)
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final aspectRatio = _controller!.value.aspectRatio;
                      if (aspectRatio <= 0) {
                        return const Center(child: CircularProgressIndicator(color: Colors.white));
                      }
                      return Center(
                        child: AspectRatio(
                          aspectRatio: aspectRatio,
                          child: CameraPreview(_controller!),
                        ),
                      );
                    },
                  ),
                ),
                
                // Face Guide Overlay
                Center(
                  child: Container(
                    width: 250,
                    height: 320,
                    decoration: BoxDecoration(
                      shape: BoxShape.rectangle,
                      borderRadius: BorderRadius.circular(125),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.5),
                        width: 3,
                      ),
                    ),
                  ),
                ),
                
                // Instruction Text
                Positioned(
                  bottom: 200,
                  left: 0,
                  right: 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing2XL),
                    child: const Text(
                      'Position your face within the circle',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                
                // Camera Controls
                Positioned(
                  bottom: 50,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      // Attendance Type Display
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacingLG,
                          vertical: AppTheme.spacingSM,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.isCheckIn ? Icons.login : Icons.logout,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: AppTheme.spacingSM),
                            Text(
                              widget.isCheckIn ? 'Check In' : 'Check Out',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: AppTheme.spacingLG),
                      
                      // Capture Button
                      GestureDetector(
                        onTap: _isProcessing ? null : _captureAndMarkAttendance,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.3),
                          ),
                          child: _isProcessing
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                )
                              : Container(
                                  margin: const EdgeInsets.all(7.5),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                      
                      const SizedBox(height: AppTheme.spacingLG),
                      
                      // Cancel Button
                      TextButton(
                        onPressed: _isProcessing ? null : () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppTheme.spacingSM,
                            horizontal: AppTheme.spacing2XL,
                          ),
                          backgroundColor: Colors.black.withOpacity(0.5),
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
                    ],
                  ),
                ),
              ],
            )
          : const Scaffold(
              backgroundColor: Colors.black,
              body: Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
            ),
    );
  }

}
