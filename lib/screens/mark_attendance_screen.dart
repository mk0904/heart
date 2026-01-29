import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:image/image.dart' as img;
import '../services/face_detection_service.dart';
import '../services/face_recognition_service.dart';
import '../services/attendance_service.dart';

class MarkAttendanceScreen extends StatefulWidget {
  const MarkAttendanceScreen({super.key});

  @override
  State<MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends State<MarkAttendanceScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  int _cameraIndex = 0;
  bool _isInitialized = false;
  bool _isProcessing = false;
  final FaceDetectionService _faceDetectionService = FaceDetectionService();
  final FaceRecognitionService _faceRecognitionService = FaceRecognitionService();
  final AttendanceService _attendanceService = AttendanceService();
  String _selectedType = 'check_in';

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

  Future<void> _toggleCamera() async {
    if (_cameras == null || _cameras!.length < 2) {
      return;
    }
    // Switch to the other camera
    final newIndex = _cameraIndex == 0 ? 1 : 0;
    await _switchCamera(newIndex);
  }

  Future<void> _captureAndMarkAttendance() async {
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

      await _attendanceService.markAttendance(
        person: person,
        type: _selectedType,
        confidence: confidence,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_selectedType == 'check_in' ? 'Check-in' : 'Check-out'} marked for ${person.name}!',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mark Attendance'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: _isInitialized
          ? Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      CameraPreview(_controller!),
                      if (_isProcessing)
                        Container(
                          color: Colors.black54,
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                                SizedBox(height: 20),
                                Text(
                                  'Processing...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      // Camera switch button
                      if (_cameras != null && _cameras!.length > 1)
                        Positioned(
                          top: 16,
                          right: 16,
                          child: FloatingActionButton(
                            mini: true,
                            onPressed: _isProcessing ? null : _toggleCamera,
                            backgroundColor: Colors.black54,
                            child: const Icon(Icons.cameraswitch),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'check_in',
                            label: Text('Check In'),
                            icon: Icon(Icons.login),
                          ),
                          ButtonSegment(
                            value: 'check_out',
                            label: Text('Check Out'),
                            icon: Icon(Icons.logout),
                          ),
                        ],
                        selected: {_selectedType},
                        onSelectionChanged: _isProcessing
                            ? null
                            : (Set<String> newSelection) {
                                setState(() {
                                  _selectedType = newSelection.first;
                                });
                              },
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isProcessing ? null : _captureAndMarkAttendance,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          child: _isProcessing
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Capture & Mark Attendance',
                                  style: TextStyle(fontSize: 16),
                                ),
                        ),
                      ),
                    ],
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
