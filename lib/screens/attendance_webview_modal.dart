import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import '../services/firebase_auth_service.dart';

enum WebFlowType { register, checkIn, checkOut }

class AttendanceWebViewModal extends StatefulWidget {
  final WebFlowType flowType;
  final Position? position;

  const AttendanceWebViewModal({
    super.key,
    required this.flowType,
    this.position,
  });

  @override
  State<AttendanceWebViewModal> createState() => _AttendanceWebViewModalState();
}

class _AttendanceWebViewModalState extends State<AttendanceWebViewModal> {
  WebViewController? _controller;
  final FirebaseAuthService _authService = FirebaseAuthService();
  bool _isLoading = true;
  bool _permissionDenied = false;

  static const String _baseUrl = 'https://face-verification-heart.vercel.app';

  @override
  void initState() {
    super.initState();
    _initAsync();
  }

  Future<void> _initAsync() async {
    // 1️⃣ Request native permissions first
    await [Permission.camera, Permission.locationWhenInUse].request();

    if (!mounted) return;

    final cameraStatus = await Permission.camera.status;
    if (cameraStatus.isPermanentlyDenied) {
      setState(() => _permissionDenied = true);
      return;
    }

    // 3️⃣ Build controller with onPermissionRequest in the constructor
    final controller = await _buildController(widget.position);
    if (mounted) setState(() => _controller = controller);
  }

  Future<WebViewController> _buildController(Position? position) async {
    final uid = _authService.currentUser?.uid ?? '';
    
    // Construct URL with location params if available
    String type = widget.flowType == WebFlowType.register ? 'register' : (widget.flowType == WebFlowType.checkIn ? 'checkin' : 'checkout');
    String url = '$_baseUrl/?uid=$uid&type=$type';
    if (position != null) {
      url += '&lat=${position.latitude}&lng=${position.longitude}';
    }

    // Platform-specific params
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      // iOS — allow inline camera + no user gesture required
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    // 3️⃣ onPermissionRequest MUST be in the constructor — not set separately
    final controller = WebViewController.fromPlatformCreationParams(
      params,
      onPermissionRequest: (request) => request.grant(),
    );

    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    
    // Add a JavaScript channel to listen for successful completion
    await controller.addJavaScriptChannel('FlutterChannel', onMessageReceived: (message) {
      if (message.message == 'success') {
        if (mounted) Navigator.of(context).pop(true);
      } else if (message.message == 'cancel') {
        if (mounted) Navigator.of(context).pop(false);
      }
    });

    controller.setNavigationDelegate(NavigationDelegate(
      onPageStarted: (_) { if (mounted) setState(() => _isLoading = true); },
      onPageFinished: (_) { if (mounted) setState(() => _isLoading = false); },
      onWebResourceError: (_) { if (mounted) setState(() => _isLoading = false); },
    ));
    await controller.setBackgroundColor(Colors.transparent);
    await controller.loadRequest(Uri.parse(url));

    return controller;
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: 0.5),
        body: SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 60, 16, 40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_permissionDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.camera_alt_outlined, size: 64, color: Color(0xFF004d40)),
              const SizedBox(height: 16),
              const Text('Camera Permission Required',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Please allow camera access in Settings to use attendance.',
                  style: TextStyle(fontSize: 14, color: Color(0xFF666666)),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: openAppSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF004d40),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Open Settings',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );
    }

    if (_controller == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF004d40), strokeWidth: 2.5),
            SizedBox(height: 12),
            Text('Requesting permissions...', style: TextStyle(fontSize: 13, color: Color(0xFF666666))),
          ],
        ),
      );
    }

    return Stack(
      children: [
        WebViewWidget(controller: _controller!),
        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(color: Color(0xFF004d40), strokeWidth: 2.5),
          ),
      ],
    );
  }
}
