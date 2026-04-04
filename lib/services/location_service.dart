import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  /// Request location permissions
  Future<bool> requestPermission() async {
    final status = await Permission.location.request();
    return status.isGranted;
  }

  /// Check if location permission is granted
  Future<bool> hasPermission() async {
    final status = await Permission.location.status;
    return status.isGranted;
  }

  /// Best-effort fix for persisting with each attendance event (high accuracy →
  /// last known → medium accuracy). Call from [markAttendance] so Firebase always
  /// gets coordinates captured at check-in/out time.
  Future<Position?> getLocationForAttendanceSnapshot() async {
    Position? p = await getCurrentLocation();
    if (p != null) return p;

    try {
      p = await Geolocator.getLastKnownPosition();
      if (p != null) return p;
    } catch (e) {
      debugPrint('getLastKnownPosition: $e');
    }

    try {
      if (!await hasPermission()) {
        final granted = await requestPermission();
        if (!granted) return null;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 25),
        ),
      );
    } catch (e) {
      debugPrint('getLocationForAttendanceSnapshot fallback: $e');
      return null;
    }
  }

  /// Get current location
  Future<Position?> getCurrentLocation() async {
    try {
      // Check if permission is granted
      if (!await hasPermission()) {
        final granted = await requestPermission();
        if (!granted) {
          return null;
        }
      }

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      // Bounded wait — avoids indefinite hangs indoors / weak GPS (Android check-in flow).
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (e) {
      debugPrint('Error getting location: $e');
      return null;
    }
  }

  /// Straight-line distance between two coordinates in **meters** (Haversine).
  double distanceBetweenMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  /// Distance in kilometers (convenience for display / legacy).
  double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return distanceBetweenMeters(lat1, lon1, lat2, lon2) / 1000;
  }

  /// [maxRadiusMeters] matches Firebase `colleges.maxDistance` (meters).
  bool isWithinGeofence(
    double userLat,
    double userLon,
    double collegeLat,
    double collegeLon,
    double maxRadiusMeters,
  ) {
    final distanceM = distanceBetweenMeters(userLat, userLon, collegeLat, collegeLon);
    return distanceM <= maxRadiusMeters;
  }
}
