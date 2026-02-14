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

      // Get current position
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      debugPrint('Error getting location: $e');
      return null;
    }
  }

  /// Calculate distance between two coordinates in kilometers using Haversine formula
  double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000; // Convert meters to km
  }

  /// Check if user is within the geofence (maxDistance in km)
  bool isWithinGeofence(
    double userLat,
    double userLon,
    double collegeLat,
    double collegeLon,
    double maxDistance,
  ) {
    final distance = calculateDistance(userLat, userLon, collegeLat, collegeLon);
    return distance <= maxDistance;
  }
}
