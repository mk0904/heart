import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class AppPermissionService {
  AppPermissionService._();

  static final AppPermissionService instance = AppPermissionService._();

  Future<void> requestStartupPermissions() async {
    try {
      await Permission.camera.request();
      await Permission.locationWhenInUse.request();
    } catch (e) {
      debugPrint('Startup permission request warning: $e');
    }
  }

  Future<PermissionStatus> requestLocationWhenInUse() {
    return Permission.locationWhenInUse.request();
  }
}
