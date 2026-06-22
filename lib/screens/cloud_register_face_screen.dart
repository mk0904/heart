import 'dart:io';

import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

import '../services/cloud_face_service.dart';
import '../services/face_detection_service.dart';
import '../services/firebase_storage_service.dart';
import '../theme/app_theme.dart';

class CloudRegisterFaceScreen extends StatefulWidget {
  const CloudRegisterFaceScreen({super.key});

  @override
  State<CloudRegisterFaceScreen> createState() =>
      _CloudRegisterFaceScreenState();
}

class _CloudRegisterFaceScreenState extends State<CloudRegisterFaceScreen> {
  final FaceDetectionService _faceDetectionService = FaceDetectionService();
  final FirebaseStorageService _storageService = FirebaseStorageService();
  final CloudFaceService _cloudFaceService = CloudFaceService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  Face? _detectedFace;
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isDetecting = false;

  Color get _statusColor =>
      _detectedFace == null ? AppTheme.warning : AppTheme.success;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
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
            content: Text('Front camera is required for face registration.'),
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
    _startLiveFeed();
  }

  void _startLiveFeed() {
    final controller = _controller;
    if (controller == null || controller.value.isStreamingImages) return;

    controller.startImageStream((image) async {
      if (_isDetecting || _isProcessing) return;
      _isDetecting = true;
      try {
        final input = _inputImageFromCameraImage(image);
        if (input == null) return;
        final faces = await _faceDetectionService.faceDetector.processImage(
          input,
        );
        if (mounted) {
          setState(
            () => _detectedFace = faces.length == 1 ? faces.first : null,
          );
        }
      } finally {
        _isDetecting = false;
      }
    });
  }

  Future<void> _stopLiveFeed() async {
    final controller = _controller;
    if (controller != null && controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
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

    final format = Platform.isIOS
        ? InputImageFormat.bgra8888
        : InputImageFormat.nv21;

    final bytes = WriteBuffer();
    for (final plane in image.planes) {
      bytes.putUint8List(plane.bytes);
    }

    return InputImage.fromBytes(
      bytes: bytes.done().buffer.asUint8List(),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
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

  Future<File> _captureCroppedFace(String prefix) async {
    final controller = _controller;
    if (controller == null) throw Exception('Camera is not ready.');

    img.Image? decoded;

    await _stopLiveFeed();
    await Future.delayed(const Duration(milliseconds: 250));
    final shot = await controller.takePicture();
    final bytes = await File(shot.path).readAsBytes();
    decoded = img.decodeImage(bytes);

    if (decoded == null) throw Exception('Could not read camera image.');

    final fixedFile = File(
      '${Directory.systemTemp.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}_fixed.jpg',
    );
    await fixedFile.writeAsBytes(img.encodeJpg(decoded));

    final face = await _faceDetectionService.detectFace(
      InputImage.fromFilePath(fixedFile.path),
    );
    if (await fixedFile.exists()) await fixedFile.delete();
    if (face == null) throw Exception('No face detected. Please try again.');

    final cropped = await _faceDetectionService.cropFace(decoded, face);
    if (cropped == null) throw Exception('Could not crop face.');

    final faceFile = File(
      '${Directory.systemTemp.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await faceFile.writeAsBytes(
      Uint8List.fromList(img.encodeJpg(cropped, quality: 90)),
    );
    return faceFile;
  }

  Future<void> _register() async {
    if (_detectedFace == null || _isProcessing) return;
    setState(() => _isProcessing = true);

    File? faceFile;
    try {
      faceFile = await _captureCroppedFace('cloud_face_reg');
      final uid = _auth.currentUser?.uid;
      if (uid == null) throw Exception('Please sign in again.');
      final faceUrl = await _storageService.uploadRegisteredFaceImage(
        faceFile,
        uid,
      );
      await _cloudFaceService.registerFace(
        faceImageFile: faceFile,
        faceImageUrl: faceUrl,
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        _startLiveFeed();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
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
                        const Text(
                          'Register face',
                          style: TextStyle(
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
                  child: _buildBottomControl(),
                ),
                if (_isProcessing)
                  Container(
                    color: Colors.black.withValues(alpha: 0.62),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: AppTheme.primaryLight,
                          ),
                          SizedBox(height: AppTheme.spacingLG),
                          Text(
                            'Saving face profile...',
                            style: TextStyle(
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

  Widget _buildBottomControl() {
    final hasFace = _detectedFace != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            hasFace ? Icons.check_circle : Icons.center_focus_strong,
            color: _statusColor,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasFace ? 'Ready' : 'Center your face',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              onPressed: hasFace && !_isProcessing ? _register : null,
              icon: const Icon(Icons.camera_alt, color: AppTheme.white),
              style: IconButton.styleFrom(
                backgroundColor: hasFace
                    ? AppTheme.primary
                    : Colors.white.withValues(alpha: 0.16),
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.16),
                shape: const CircleBorder(),
              ),
            ),
          ),
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
    final button = SizedBox(
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
    return button;
  }
}
