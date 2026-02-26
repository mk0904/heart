import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_auth_service.dart';
import 'firestore_service.dart';
import 'location_service.dart';

class AttendanceService {
  static AttendanceService? _instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuthService _authService = FirebaseAuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final LocationService _locationService = LocationService();
  bool _isInitialized = false;

  // Private constructor for singleton
  AttendanceService._internal();

  // Factory constructor returns the singleton instance
  factory AttendanceService() {
    _instance ??= AttendanceService._internal();
    return _instance!;
  }

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
  }

  // Getter to check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Check if user is currently checked in (has more check-ins than check-outs today)
  Future<bool> isCurrentlyCheckedIn() async {
    final user = await _authService.getCurrentUser();
    if (user == null) return false;

    try {
      final todayRecord = await _getTodayRecord(user.uid);
      if (todayRecord != null) {
        final data = todayRecord.data() as Map<String, dynamic>?;
        if (data != null) {
          // Check events array
          final events = List<Map<String, dynamic>>.from(
            (data['events'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? []
          );
          
          if (events.isNotEmpty) {
            // Sort by time to ensure correct order
            events.sort((a, b) => (a['time'] as String).compareTo(b['time'] as String));
            return events.last['type'] == 'check_in';
          }
          
          // Fallback to top-level fields only if events is empty
          if (data['checkInTime'] != null && data['checkoutTime'] == null) {
            return true;
          }
        }
      }
    } catch (e) {
      // Silent error
    }

    return false;
  }

  /// Get college details including time settings and geofencing
  Future<Map<String, dynamic>?> getCollegeDetails() async {
    final user = await _authService.getCurrentUser();
    if (user == null || user.collegeId == null) return null;

    try {
      final college = await _firestoreService.getCollege(user.collegeId!);
      if (college != null) {
        // Handle type conversion for startTime and endTime (can be int or double)
        final startTimeRaw = college['startTime'];
        final endTimeRaw = college['endTime'];
        final maxDistanceRaw = college['maxDistance'];
        final latitudeRaw = college['latitude'];
        final longitudeRaw = college['longitude'];
        
        return {
          'startTime': startTimeRaw is int ? startTimeRaw : (startTimeRaw as num?)?.toInt() ?? 9,
          'endTime': endTimeRaw is int ? endTimeRaw : (endTimeRaw as num?)?.toInt() ?? 17,
          'maxDistance': maxDistanceRaw is double ? maxDistanceRaw : (maxDistanceRaw is int ? maxDistanceRaw.toDouble() : 1.0),
          'latitude': latitudeRaw is double ? latitudeRaw : (latitudeRaw is int ? latitudeRaw.toDouble() : null),
          'longitude': longitudeRaw is double ? longitudeRaw : (longitudeRaw is int ? longitudeRaw.toDouble() : null),
        };
      }
    } catch (e) {
      // print('Error fetching college details: $e');
    }
    return null;
  }

  /// Check if check-in is allowed (Midnight <= Now < Start Time)
  Future<bool> isCheckInAllowed() async {
    final details = await getCollegeDetails();
    if (details == null) return true; // If no settings, allow anytime

    final now = DateTime.now();
    final currentHour = now.hour;
    final startHourRaw = details['startTime'];
    
    final startHour = startHourRaw is int ? startHourRaw : (startHourRaw as num).toInt();

    // Allowed if current hour is strictly less than start hour
    return currentHour < startHour;
  }

  /// Check if check-out is allowed (End Time <= Now < Midnight)
  Future<bool> isCheckOutAllowed() async {
    final details = await getCollegeDetails();
    if (details == null) return true; // If no settings, allow anytime

    final now = DateTime.now();
    final currentHour = now.hour;
    final endHourRaw = details['endTime'];
    
    final endHour = endHourRaw is int ? endHourRaw : (endHourRaw as num).toInt();

    // Allowed if current hour is greater than or equal to end hour
    return currentHour >= endHour;
  }

  /// Check if user is within geofence
  Future<Map<String, dynamic>> validateGeofence() async {
    try {
      // Get college details
      final collegeDetails = await getCollegeDetails();
      if (collegeDetails == null) {
        return {
          'valid': true,
          'message': 'College details not found',
        };
      }

      // Get user's current location
      final position = await _locationService.getCurrentLocation();
      if (position == null) {
        return {
          'valid': false,
          'message': 'Unable to get your location. Please enable location services.',
        };
      }

      // Check if within geofence - handle both int and double types from Firebase
      final collegeLatRaw = collegeDetails['latitude'];
      final collegeLonRaw = collegeDetails['longitude'];
      final maxDistanceRaw = collegeDetails['maxDistance'];
      
      if (collegeLatRaw == null || collegeLonRaw == null) {
        return {
          'valid': false,
          'message': 'College location not configured',
        };
      }
      
      final collegeLat = (collegeLatRaw is int) ? collegeLatRaw.toDouble() : (collegeLatRaw as num).toDouble();
      final collegeLon = (collegeLonRaw is int) ? collegeLonRaw.toDouble() : (collegeLonRaw as num).toDouble();
      final maxDistance = (maxDistanceRaw is int) 
          ? maxDistanceRaw.toDouble() 
          : (maxDistanceRaw is double ? maxDistanceRaw : (maxDistanceRaw as num).toDouble());

      final isWithin = _locationService.isWithinGeofence(
        position.latitude,
        position.longitude,
        collegeLat,
        collegeLon,
        maxDistance,
      );

      if (!isWithin) {
        final distance = _locationService.calculateDistance(
          position.latitude,
          position.longitude,
          collegeLat,
          collegeLon,
        );
        return {
          'valid': false,
          'message': 'You are ${distance.toStringAsFixed(2)} km away from college. Maximum allowed distance is ${maxDistance.toStringAsFixed(1)} km.',
          'distance': distance,
          'maxDistance': maxDistance,
        };
      }

      return {
        'valid': true,
        'message': 'Location verified',
      };
    } catch (e) {
      return {
        'valid': false,
        'message': 'Error validating location: $e',
      };
    }
  }

  /// Get today's attendance record for a user (if exists)
  Future<DocumentSnapshot?> _getTodayRecord(String userId) async {
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      
      // Fetch all records for this user and filter by date
      final allRecords = await _firestore
          .collection('attendance')
          .where('userId', isEqualTo: userId)
          .get();

      // Find today's record
      for (var doc in allRecords.docs) {
        final data = doc.data();
        final dateStr = data['date'] as String?;
        if (dateStr == todayStart.toIso8601String().split('T')[0]) {
          return doc;
        }
        // Also check timestamp field for backward compatibility
        final timestamp = data['timestamp'] as String?;
        if (timestamp != null) {
          try {
            final recordTime = DateTime.parse(timestamp);
            if (recordTime.isAfter(todayStart) && recordTime.isBefore(todayEnd)) {
              return doc;
            }
          } catch (e) {
            // Skip invalid timestamps
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get attendance history from Firebase strictly
  Future<List<Map<String, dynamic>>> getAttendanceHistory() async {
    try {
      final user = await _authService.getCurrentUser();
      if (user == null) return [];

      final querySnapshot = await _firestore
          .collection('attendance')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .get();

      List<Map<String, dynamic>> allEvents = [];
          
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        
        // Convert old singular records to event format if needed
        if (data['events'] != null) {
          final eventsList = (data['events'] as List).map((e) => e as Map<String, dynamic>).toList();
          allEvents.addAll(eventsList);
        } else if (data['type'] != null && data['timestamp'] != null) {
          // Backward compatibility for old records
          allEvents.add({
            'type': data['type'],
            'time': data['timestamp'],
            'confidence': data['confidence'] ?? 1.0,
          });
        }
      }
      
      // Sort all events by time descending
      allEvents.sort((a, b) {
        try {
          final timeA = DateTime.parse(a['time'] as String);
          final timeB = DateTime.parse(b['time'] as String);
          return timeB.compareTo(timeA); // Descending
        } catch (e) {
          return 0;
        }
      });
      
      return allEvents;
    } catch (e) {
      return [];
    }
  }

  /// Get daily grouped attendance history
  Future<List<Map<String, dynamic>>> getDailyAttendanceHistory() async {
    final user = await _authService.getCurrentUser();
    if (user == null) return [];

    try {
      final querySnapshot = await _firestore
          .collection('attendance')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .get();

      List<Map<String, dynamic>> dailyRecords = [];
      
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final dateStr = data['date'] as String? ?? 
            (data['timestamp'] != null ? data['timestamp'].toString().split('T')[0] : '');
            
        if (dateStr.isEmpty) continue;

        final events = List<Map<String, dynamic>>.from(
          (data['events'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? []
        );

        dailyRecords.add({
          'date': dateStr,
          'checkIn': data['checkInTime'],
          'checkOut': data['checkoutTime'],
          'status': data['type'],
          'events': events,
        });
      }
      
      return dailyRecords;
    } catch (e) {
      return [];
    }
  }
}
