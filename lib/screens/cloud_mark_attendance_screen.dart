import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

import '../services/attendance_service.dart';
import '../services/cloud_face_service.dart';
import '../services/face_detection_service.dart';
import '../services/firebase_auth_service.dart';
import '../theme/app_theme.dart';

class CloudMarkAttendanceScreen extends StatefulWidget {
  const CloudMarkAttendanceScreen({super.key, required this.isCheckIn});

  final bool isCheckIn;

  @override
  State<CloudMarkAttendanceScreen> createState() =>
      _CloudMarkAttendanceScreenState();
}

class _CloudMarkAttendanceScreenState extends State<CloudMarkAttendanceScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  final CloudFaceService _cloudFaceService = CloudFaceService();
  final FaceDetectionService _faceDetectionService = FaceDetectionService();
  final FirebaseAuthService _authService = FirebaseAuthService();

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _livenessVerified = false;
  bool _isBlinking = false;
  bool _canProcessStream = true;
  DateTime? _lastProcessTime;
  Uint8List? _lastFrameBytes;
  int _lastFrameWidth = 0;
  int _lastFrameHeight = 0;
  String _feedbackText = 'Position your face in the circle';
  Position? _position;

  String get _actionTitle => widget.isCheckIn ? 'Check in' : 'Check out';

  Color get _statusColor {
    if (_livenessVerified) return AppTheme.success;
    if (_isBlinking) return AppTheme.info;
    if (_feedbackText.contains('No face') ||
        _feedbackText.contains('Multiple') ||
        _feedbackText.contains('try')) {
      return AppTheme.warning;
    }
    return AppTheme.white;
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final ok = await _finalVerification();
    if (!mounted || !ok) return;
    await _initializeCamera();
  }

  Future<bool> _finalVerification() async {
    final validTime = widget.isCheckIn
        ? await _attendanceService.isCheckInAllowed()
        : await _attendanceService.isCheckOutAllowed();
    if (!mounted) return false;
    if (!validTime) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isCheckIn
                ? 'Check-in allowed only before college start time'
                : 'Check-out allowed only after college hours',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      Navigator.pop(context);
      return false;
    }

    final geofence = await _attendanceService.validateGeofence();
    if (!mounted) return false;
    if (geofence['valid'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(geofence['message'] ?? 'Location validation failed.'),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.pop(context);
      return false;
    }

    _position = await _getAttendancePosition();
    if (_position == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location permission is required to mark attendance.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
      }
      return false;
    }

    return true;
  }

  Future<Position?> _getAttendancePosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _initializeCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) Navigator.pop(context);
      return;
    }

    _cameras = await availableCameras();
    if (_cameras.isEmpty) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final frontIndex = _cameras.indexWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
    );
    if (frontIndex < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Front camera is required for attendance.'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
      }
      return;
    }
    await _initializeFrontCamera(_cameras[frontIndex]);
  }

  Future<void> _initializeFrontCamera(CameraDescription camera) async {
    await _controller?.dispose();
    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    await _controller!.initialize();
    if (!mounted) return;
    setState(() {
      _isInitialized = true;
    });
    _startImageStream();
  }

  void _startImageStream() {
    final controller = _controller;
    if (controller == null || controller.value.isStreamingImages) return;

    controller.startImageStream((image) {
      if (Platform.isIOS) {
        _lastFrameBytes = Uint8List.fromList(image.planes[0].bytes);
        _lastFrameWidth = image.width;
        _lastFrameHeight = image.height;
      }
      if (_isProcessing || _livenessVerified || !_canProcessStream) return;
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
      final input = _inputImageFromCameraImage(image);
      if (input == null) return;
      final faces = await _faceDetectionService.faceDetector.processImage(
        input,
      );
      if (!mounted) return;
      if (faces.isEmpty) {
        setState(() {
          _feedbackText = 'No face detected';
          _isBlinking = false;
        });
      } else if (faces.length > 1) {
        setState(() {
          _feedbackText = 'Multiple faces detected';
          _isBlinking = false;
        });
      } else {
        _checkLiveness(faces.first);
      }
    } finally {
      _canProcessStream = true;
    }
  }

  void _checkLiveness(Face face) {
    final leftOpen = face.leftEyeOpenProbability;
    final rightOpen = face.rightEyeOpenProbability;
    if (leftOpen == null || rightOpen == null) {
      setState(() => _feedbackText = 'Keep face steady');
      return;
    }

    final eyesClosed = leftOpen < 0.35 && rightOpen < 0.35;
    final eyesOpen = leftOpen > 0.85 && rightOpen > 0.85;

    if (eyesOpen && _isBlinking) {
      setState(() {
        _isBlinking = false;
        _livenessVerified = true;
        _feedbackText = 'Verified. Marking attendance...';
      });
      _stopStreamAndCapture();
    } else if (eyesClosed) {
      setState(() {
        _isBlinking = true;
        _feedbackText = 'Eyes closed...';
      });
    } else if (!_isBlinking) {
      setState(() => _feedbackText = 'Please blink to verify you are human');
    }
  }

  Future<void> _stopStreamAndCapture() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) await _captureAndVerify();
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final controller = _controller;
    if (controller == null) return null;

    final camera = controller.description;
    final rotation = Platform.isIOS
        ? InputImageRotationValue.fromRawValue(camera.sensorOrientation)
        : InputImageRotationValue.fromRawValue(
            (camera.sensorOrientation +
                    (_orientations[controller.value.deviceOrientation] ?? 0)) %
                360,
          );
    if (rotation == null) return null;

    final bytes = WriteBuffer();
    for (final plane in image.planes) {
      bytes.putUint8List(plane.bytes);
    }

    return InputImage.fromBytes(
      bytes: bytes.done().buffer.asUint8List(),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: Platform.isIOS
            ? InputImageFormat.bgra8888
            : InputImageFormat.nv21,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  Future<File> _captureCroppedFace() async {
    final controller = _controller;
    if (controller == null) throw Exception('Camera is not ready.');
    
    img.Image? decoded;

    if (Platform.isIOS && _lastFrameBytes != null) {
      final frameBytes = _lastFrameBytes!;
      decoded = img.Image.fromBytes(
        width: _lastFrameWidth,
        height: _lastFrameHeight,
        bytes: frameBytes.buffer,
        order: img.ChannelOrder.bgra,
      );
      final sensorOrientation = controller.description.sensorOrientation;
      decoded = img.copyRotate(decoded, angle: sensorOrientation);
      if (controller.description.lensDirection == CameraLensDirection.front) {
        decoded = img.flipHorizontal(decoded);
      }
    } else {
      final shot = await controller.takePicture().timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw TimeoutException('Camera capture timed out.'),
      );
      final bytes = await File(shot.path).readAsBytes();
      decoded = img.decodeImage(bytes);
    }
    
    if (decoded == null) throw Exception('Could not read camera image.');

    final fixedFile = File(
      '${Directory.systemTemp.path}/cloud_att_${DateTime.now().millisecondsSinceEpoch}_fixed.jpg',
    );
    await fixedFile.writeAsBytes(img.encodeJpg(decoded));

    final face = await _faceDetectionService.detectFace(
      InputImage.fromFilePath(fixedFile.path),
    );
    if (await fixedFile.exists()) await fixedFile.delete();
    if (face == null) throw Exception('Face detection failed on capture.');

    final cropped = await _faceDetectionService.cropFace(decoded, face);
    if (cropped == null) throw Exception('Could not crop face.');

    final faceFile = File(
      '${Directory.systemTemp.path}/cloud_att_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await faceFile.writeAsBytes(
      Uint8List.fromList(img.encodeJpg(cropped, quality: 85)),
    );
    return faceFile;
  }

  Future<void> _captureAndVerify() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    File? faceFile;
    try {
      final user = await _authService.getCurrentUser();
      if (user == null) throw Exception('Please sign in again.');

      faceFile = await _captureCroppedFace();
      final date = DateTime.now().toIso8601String().split('T')[0];
      final type = widget.isCheckIn ? 'check_in' : 'check_out';

      final result = await _cloudFaceService.verifyAttendance(
        faceImageFile: faceFile,
        type: type,
        dateYyyyMmDd: date,
        latitude: _position?.latitude,
        longitude: _position?.longitude,
      );

      if (result['matched'] != true) {
        throw Exception('Face did not match the registered profile.');
      }

      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _livenessVerified = false;
          _isBlinking = false;
          _feedbackText = 'Please try again';
        });
        _startImageStream();
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Failed'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (faceFile != null && await faceFile.exists()) await faceFile.delete();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetectionService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isInitialized && _controller != null
          ? Stack(
              children: [
                Positioned.fill(child: _buildCameraPreview()),
                Positioned.fill(child: _buildSoftShade()),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        _CircleButton(
                          icon: Icons.close,
                          onPressed: _isProcessing
                              ? null
                              : () => Navigator.pop(context),
                        ),
                        const Spacer(),
                        Text(
                          _actionTitle,
                          style: const TextStyle(
                            color: AppTheme.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(width: 44),
                      ],
                    ),
                  ),
                ),
                Center(child: _buildScanFrame()),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 42,
                  child: _buildStatusText(),
                ),
                if (_isProcessing)
                  Container(
                    color: Colors.black.withValues(alpha: 0.62),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            color: AppTheme.primaryLight,
                          ),
                          const SizedBox(height: AppTheme.spacingLG),
                          Text(
                            'Marking attendance...',
                            style: const TextStyle(
                              color: AppTheme.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            )
          : _buildLoadingState(),
    );
  }

  Widget _buildCameraPreview() {
    final controller = _controller!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = controller.value.previewSize;
        if (previewSize == null) return CameraPreview(controller);
        final isPortrait = constraints.maxHeight >= constraints.maxWidth;
        final previewWidth = isPortrait ? previewSize.height : previewSize.width;
        final previewHeight = isPortrait ? previewSize.width : previewSize.height;

        return ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: previewWidth,
              height: previewHeight,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSoftShade() {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.34),
              Colors.transparent,
              Colors.black.withValues(alpha: 0.50),
            ],
            stops: const [0.0, 0.48, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _buildScanFrame() {
    return SizedBox(
      width: 248,
      height: 318,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(124),
                border: Border.all(
                  color: _statusColor.withValues(alpha: 0.92),
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusText() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            _livenessVerified
                ? Icons.check_circle
                : (_isBlinking ? Icons.visibility_off : Icons.visibility),
            color: _statusColor,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _feedbackText,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 28),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppTheme.primaryLight),
          SizedBox(height: AppTheme.spacingLG),
          Text(
            'Preparing camera...',
            style: TextStyle(
              color: AppTheme.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: AppTheme.white),
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withValues(alpha: 0.42),
          disabledBackgroundColor: Colors.black.withValues(alpha: 0.20),
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}
