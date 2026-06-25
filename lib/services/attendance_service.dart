import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/attendance_record.dart';
import '../models/daily_attendance.dart';
import '../models/person.dart';
import '../utils/user_friendly_errors.dart';
import 'connectivity_service.dart';
import 'firebase_auth_service.dart';
import 'firestore_service.dart';
import 'location_service.dart';
import 'true_time_service.dart';

/// Attendance now uses the cloud face backend on every platform.
bool _useNativeAndroidAttendance() => false;

/// Opens a Hive box; if on-disk data is corrupt (frame read errors), deletes and recreates.
Future<Box<T>> _openHiveBoxOrRecreate<T>(String name) async {
  try {
    return await Hive.openBox<T>(name);
  } catch (_) {
    try {
      if (Hive.isBoxOpen(name)) {
        await Hive.box<T>(name).close();
      }
    } catch (_) {}
    try {
      await Hive.deleteBoxFromDisk(name);
    } catch (_) {}
    return await Hive.openBox<T>(name);
  }
}

/// Parsed college schedule boundary (Firestore may use int hour, `"HH:mm"` 24h, or 12h with am/pm).
class _CollegeHm {
  const _CollegeHm(this.hour, this.minute);
  final int hour;
  final int minute;

  int get minutesFromMidnight => hour * 60 + minute;
}

/// Wall-clock time only — ignores calendar date (e.g. Jan 1 placeholder on Timestamps).
_CollegeHm _timeOfDayFromDateTime(DateTime dt) {
  final local = dt.isUtc ? dt.toLocal() : dt;
  return _CollegeHm(local.hour, local.minute);
}

_CollegeHm _parseCollegeScheduleField(
  dynamic raw, {
  int defaultHour = 9,
  int defaultMinute = 0,
}) {
  if (raw == null) {
    return _CollegeHm(defaultHour.clamp(0, 23), defaultMinute.clamp(0, 59));
  }
  if (raw is Timestamp) {
    return _timeOfDayFromDateTime(raw.toDate());
  }
  if (raw is DateTime) {
    return _timeOfDayFromDateTime(raw);
  }
  if (raw is int) {
    return _CollegeHm(raw.clamp(0, 23), 0);
  }
  if (raw is double) {
    return _CollegeHm(raw.round().clamp(0, 23), 0);
  }
  if (raw is num) {
    return _CollegeHm(raw.toInt().clamp(0, 23), 0);
  }
  if (raw is String) {
    var t = raw.trim();
    if (t.isEmpty) {
      return _CollegeHm(defaultHour.clamp(0, 23), defaultMinute.clamp(0, 59));
    }

    final m12 = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(am|pm)\s*$',
      caseSensitive: false,
    ).firstMatch(t);
    if (m12 != null) {
      var h = int.parse(m12.group(1)!);
      final min = int.parse(m12.group(2)!).clamp(0, 59);
      final ap = m12.group(3)!.toLowerCase();
      if (ap == 'pm' && h != 12) {
        h += 12;
      }
      if (ap == 'am' && h == 12) {
        h = 0;
      }
      return _CollegeHm(h.clamp(0, 23), min);
    }

    final m24 = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(t);
    if (m24 != null) {
      final h = int.parse(m24.group(1)!);
      final min = int.parse(m24.group(2)!);
      if (h >= 0 && h <= 23 && min >= 0 && min <= 59) {
        return _CollegeHm(h, min);
      }
    }

    final onlyHour = int.tryParse(t);
    if (onlyHour != null && !t.contains(':')) {
      return _CollegeHm(onlyHour.clamp(0, 23), 0);
    }

    final dt = DateTime.tryParse(t);
    if (dt != null) {
      return _timeOfDayFromDateTime(dt);
    }
  }
  return _CollegeHm(defaultHour.clamp(0, 23), defaultMinute.clamp(0, 59));
}

class AttendanceService {
  static AttendanceService? _instance;
  Box<Person>? _personsBox;
  Box<AttendanceRecord>? _attendanceBox;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuthService _authService = FirebaseAuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final LocationService _locationService = LocationService();
  final ConnectivityService _connectivityService = ConnectivityService();
  bool _isInitialized = false;
  bool _isSyncing = false;
  Timer? _autoCheckoutTimer;
  Future<void>? _initFuture;

  // Private constructor for singleton
  AttendanceService._internal();

  // Factory constructor returns the singleton instance
  factory AttendanceService() {
    _instance ??= AttendanceService._internal();
    return _instance!;
  }

  /// Idempotent. Safe to await from native Android screens — dedupes concurrent in-flight init from [main].
  Future<void> ensureInitialized() => init();

  Future<void> init() async {
    if (_initFuture != null) {
      await _initFuture;
      return;
    }

    if (_isInitialized) {
      if (!_useNativeAndroidAttendance()) return;
      if (_personsBox != null && _attendanceBox != null) return;
    }

    final run = _performInit();
    _initFuture = run;
    try {
      await run;
    } finally {
      _initFuture = null;
    }
  }

  Future<void> _performInit() async {
    if (!_useNativeAndroidAttendance()) {
      _isInitialized = true;
      return;
    }

    await Hive.initFlutter();

    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(PersonAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(AttendanceRecordAdapter());
    }

    Box<Person>? persons;
    Box<AttendanceRecord>? attendance;
    try {
      persons = await _openHiveBoxOrRecreate<Person>('persons');
      attendance = await _openHiveBoxOrRecreate<AttendanceRecord>('attendance');
    } catch (_) {
      await persons?.close();
      await attendance?.close();
      persons = null;
      attendance = null;
      rethrow;
    }
    _personsBox = persons;
    _attendanceBox = attendance;

    _isInitialized = true;

    syncCurrentUserEmbedding();

    checkAutoCheckout();

    _autoCheckoutTimer?.cancel();
    _autoCheckoutTimer = Timer.periodic(const Duration(hours: 1), (timer) {
      checkAutoCheckout();
    });
  }

  /// Sync current user's face embedding from Firebase to local storage
  Future<void> syncCurrentUserEmbedding() async {
    if (!_useNativeAndroidAttendance() || _personsBox == null) return;
    try {
      final user = await _authService.getCurrentUser();
      if (user == null) return;

      // Check if already exists in local storage
      final existingPerson = _personsBox!.get(user.uid);
      if (existingPerson != null) {
        // Already synced, skip
        return;
      }

      // Fetch from Firebase
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        final faceEmbedding = data?['faceEmbedding'];
        final faceRegistered = data?['faceRegistered'] ?? false;

        if (faceRegistered && faceEmbedding != null && faceEmbedding is List) {
          // Convert to List<double>
          final firebaseEmbedding = faceEmbedding
              .map((e) => (e as num).toDouble())
              .toList();

          // Store in local Hive storage
          final person = Person(
            id: user.uid,
            name: user.name,
            employeeId: user.uid,
            faceEmbedding: firebaseEmbedding,
            registeredAt: TrueTimeService.now(),
          );

          await _personsBox!.put(user.uid, person);
        }
      }
    } catch (e) {
      // Error is non-critical, continue silently
    }
  }

  // Getter to check if service is initialized
  bool get isInitialized => _isInitialized;

  Future<void> registerPerson({
    required String name,
    required String employeeId,
    required List<double> faceEmbedding,
  }) async {
    throw UnsupportedError(
      'Local face registration has been removed. Use CloudFaceService instead.',
    );
  }

  Future<void> registerPersonWithFirebase({
    required String name,
    required String employeeId,
    required List<double> faceEmbedding,
    Object? faceImageFile,
  }) async {
    throw UnsupportedError(
      'Local face registration has been removed. Use CloudFaceService instead.',
    );
  }

  Future<Person?> recognizePerson(List<double> embedding) async {
    throw UnsupportedError(
      'Local face matching has been removed. Use CloudFaceService instead.',
    );
  }

  /// Check if user is currently checked in (has more check-ins than check-outs today)
  Future<bool> isCurrentlyCheckedIn() async {
    final user = await _authService.getCurrentUser();
    if (user == null) return false;

    final now = TrueTimeService.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    // final dateStr = todayStart.toIso8601String().split('T')[0];

    // Check Firebase first
    try {
      final todayRecord = await _getTodayRecord(user.uid);
      if (todayRecord != null) {
        final data = todayRecord.data() as Map<String, dynamic>?;
        if (data != null) {
          // Check events array
          final events = List<Map<String, dynamic>>.from(
            (data['events'] as List?)?.map(
                  (e) => Map<String, dynamic>.from(e as Map),
                ) ??
                [],
          );

          if (events.isNotEmpty) {
            // Sort by time to ensure correct order
            events.sort(
              (a, b) => (a['time'] as String).compareTo(b['time'] as String),
            );
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

    // Fallback to local storage (check for check-in without check-out) — Android native only
    if (!_useNativeAndroidAttendance() ||
        !_isInitialized ||
        _attendanceBox == null) {
      return false;
    }
    final todayRecords = _attendanceBox!.values
        .where(
          (r) =>
              r.employeeId == user.uid &&
              r.timestamp.year == todayStart.year &&
              r.timestamp.month == todayStart.month &&
              r.timestamp.day == todayStart.day,
        )
        .toList();

    if (todayRecords.isNotEmpty) {
      // Count check-ins vs check-outs
      final checkInCount = todayRecords
          .where((r) => r.type == 'check_in')
          .length;
      final checkOutCount = todayRecords
          .where((r) => r.type == 'check_out')
          .length;
      return checkInCount > checkOutCount;
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
        var startTimeRaw = college['startTime'];
        var endTimeRaw = college['endTime'];
        final maxDistanceRaw = college['maxDistance'];
        final latitudeRaw = college['latitude'];
        final longitudeRaw = college['longitude'];
        final timeSlotRulesRaw = college['timeSlotRules'];

        // Apply timeSlotRules logic locally
        if (timeSlotRulesRaw is List) {
          for (var ruleRaw in timeSlotRulesRaw) {
            if (ruleRaw is Map) {
              final ruleRole = ruleRaw['role']?.toString() ?? 'Any';
              final ruleEmp = ruleRaw['employmentType']?.toString() ?? 'Any';
              
              bool roleMatch = ruleRole == 'Any' || ruleRole == user.role;
              bool empMatch = ruleEmp == 'Any' || ruleEmp == user.employmentType;
              
              if (roleMatch && empMatch) {
                if (ruleRaw['startTime'] != null) startTimeRaw = ruleRaw['startTime'];
                if (ruleRaw['endTime'] != null) endTimeRaw = ruleRaw['endTime'];
                break; // Use the first matching rule
              }
            }
          }
        }

        final start = _parseCollegeScheduleField(
          startTimeRaw,
          defaultHour: 9,
          defaultMinute: 0,
        );
        final end = _parseCollegeScheduleField(
          endTimeRaw,
          defaultHour: 17,
          defaultMinute: 0,
        );

        return {
          'startHour': start.hour,
          'startMinute': start.minute,
          'endHour': end.hour,
          'endMinute': end.minute,
          // Legacy: hour component only (prefer startHour/startMinute for display & logic).
          'startTime': start.hour,
          'endTime': end.hour,
          // Radius from college coordinates, in **meters** (Firebase `maxDistance`).
          'maxDistance': maxDistanceRaw is double
              ? maxDistanceRaw
              : (maxDistanceRaw is int ? maxDistanceRaw.toDouble() : 500.0),
          'latitude': latitudeRaw is double
              ? latitudeRaw
              : (latitudeRaw is int ? latitudeRaw.toDouble() : null),
          'longitude': longitudeRaw is double
              ? longitudeRaw
              : (longitudeRaw is int ? longitudeRaw.toDouble() : null),
        };
      }
    } catch (e) {
      // print('Error fetching college details: $e');
    }
    return null;
  }

  /// Get college time settings (for backward compatibility)
  Future<Map<String, int>?> getCollegeTimeSettings() async {
    final details = await getCollegeDetails();
    if (details == null) return null;
    return {
      'startHour': details['startHour'] as int,
      'endHour': details['endHour'] as int,
      'startMinute': details['startMinute'] as int? ?? 0,
      'endMinute': details['endMinute'] as int? ?? 0,
    };
  }

  /// Check if current time is within college hours
  Future<bool> isWithinCollegeHours() async {
    final details = await getCollegeDetails();
    if (details == null) return true; // If no settings, allow anytime

    final now = TrueTimeService.now();
    final nowMins = now.hour * 60 + now.minute;
    final startMins =
        (details['startHour'] as int) * 60 +
        (details['startMinute'] as int? ?? 0);
    final endMins =
        (details['endHour'] as int) * 60 + (details['endMinute'] as int? ?? 0);

    return nowMins >= startMins && nowMins < endMins;
  }

  /// Check if check-in is allowed (Midnight <= Now < Start Time)
  Future<bool> isCheckInAllowed() async {
    final details = await getCollegeDetails();
    if (details == null) return true; // If no settings, allow anytime

    final now = TrueTimeService.now();
    final nowMins = now.hour * 60 + now.minute;
    final startMins =
        (details['startHour'] as int) * 60 +
        (details['startMinute'] as int? ?? 0);

    // Allowed if strictly before college start (same day, wall-clock).
    return nowMins < startMins;
  }

  /// Check if check-out is allowed (End Time <= Now < Midnight)
  Future<bool> isCheckOutAllowed() async {
    final details = await getCollegeDetails();
    if (details == null) return true; // If no settings, allow anytime

    final now = TrueTimeService.now();
    final nowMins = now.hour * 60 + now.minute;
    final endMins =
        (details['endHour'] as int) * 60 + (details['endMinute'] as int? ?? 0);

    return nowMins >= endMins;
  }

  /// Check if user is within geofence
  Future<Map<String, dynamic>> validateGeofence() async {
    try {
      // Get college details
      final collegeDetails = await getCollegeDetails();
      if (collegeDetails == null) {
        return {'valid': true, 'message': 'College details not found'};
      }

      // Get user's current location
      final position = await _locationService.getCurrentLocation();
      if (position == null) {
        return {
          'valid': false,
          'message':
              'Unable to get your location. Please enable location services.',
        };
      }

      // Check if within geofence - handle both int and double types from Firebase
      final collegeLatRaw = collegeDetails['latitude'];
      final collegeLonRaw = collegeDetails['longitude'];
      final maxDistanceRaw = collegeDetails['maxDistance'];

      if (collegeLatRaw == null || collegeLonRaw == null) {
        return {'valid': false, 'message': 'College location not configured'};
      }

      final collegeLat = (collegeLatRaw is int)
          ? collegeLatRaw.toDouble()
          : (collegeLatRaw as num).toDouble();
      final collegeLon = (collegeLonRaw is int)
          ? collegeLonRaw.toDouble()
          : (collegeLonRaw as num).toDouble();
      final maxDistanceMeters = (maxDistanceRaw is int)
          ? maxDistanceRaw.toDouble()
          : (maxDistanceRaw is double
                ? maxDistanceRaw
                : (maxDistanceRaw as num).toDouble());

      final isWithin = _locationService.isWithinGeofence(
        position.latitude,
        position.longitude,
        collegeLat,
        collegeLon,
        maxDistanceMeters,
      );

      if (!isWithin) {
        final distanceM = _locationService.distanceBetweenMeters(
          position.latitude,
          position.longitude,
          collegeLat,
          collegeLon,
        );
        return {
          'valid': false,
          'message': 'You are not in the bounded area for marking attendance.',
          'distanceMeters': distanceM,
          'maxDistanceMeters': maxDistanceMeters,
          'distance': distanceM / 1000,
          'maxDistance': maxDistanceMeters,
        };
      }

      return {'valid': true, 'message': 'Location verified'};
    } catch (e) {
      return {'valid': false, 'message': UserFriendlyErrors.message(e)};
    }
  }

  /// Auto-checkout the current user if they haven't checked out by midnight yesterday
  Future<void> checkAutoCheckout() async {
    try {
      final user = await _authService.getCurrentUser();
      if (user == null) return;

      final now = TrueTimeService.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      // Get yesterday's date
      final yesterday = todayStart.subtract(const Duration(days: 1));
      final yesterdayStr = yesterday.toIso8601String().split('T')[0];

      // Find current user's attendance record for yesterday
      final userRecords = await _firestore
          .collection('attendance')
          .where('userId', isEqualTo: user.uid)
          .get();

      // Filter yesterday's records in memory to avoid index requirements for date field
      final yesterdayRecords = userRecords.docs.where((doc) {
        final data = doc.data();
        final dateStr = data['date'] as String?;
        if (dateStr == yesterdayStr) return true;

        // Also check timestamp field for backward compatibility
        final timestamp = data['timestamp'] as String?;
        if (timestamp != null) {
          try {
            final recordTime = DateTime.parse(timestamp);
            final recordDate = DateTime(
              recordTime.year,
              recordTime.month,
              recordTime.day,
            );
            return recordDate.year == yesterday.year &&
                recordDate.month == yesterday.month &&
                recordDate.day == yesterday.day;
          } catch (e) {
            return false;
          }
        }
        return false;
      }).toList();

      for (var doc in yesterdayRecords) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

        // Get events array
        final events = List<Map<String, dynamic>>.from(
          (data['events'] as List?)?.map(
                (e) => Map<String, dynamic>.from(e as Map),
              ) ??
              [],
        );

        // If events is empty but we have check-in/out fields, reconstruct once
        if (events.isEmpty) {
          if (data['checkInTime'] != null) {
            events.add({
              'type': 'check_in',
              'time': data['checkInTime'] as String,
              'confidence':
                  (data['checkInConfidence'] as num?)?.toDouble() ?? 0.0,
            });
          }
          if (data['checkoutTime'] != null) {
            events.add({
              'type': 'check_out',
              'time': data['checkoutTime'] as String,
              'confidence':
                  (data['checkoutConfidence'] as num?)?.toDouble() ?? 0.0,
            });
          }
        }

        // Sort to be sure
        if (events.isNotEmpty) {
          events.sort(
            (a, b) => (a['time'] as String).compareTo(b['time'] as String),
          );
        }

        // If last event is check_in, auto-checkout at 11:59 PM
        if (events.isNotEmpty && events.last['type'] == 'check_in') {
          final midnight = DateTime(
            yesterday.year,
            yesterday.month,
            yesterday.day,
            23,
            59,
            59,
          );
          Map<String, dynamic>? lastIn;
          for (var i = events.length - 1; i >= 0; i--) {
            if (events[i]['type'] == 'check_in') {
              lastIn = events[i];
              break;
            }
          }
          num? lat = lastIn?['latitude'] as num? ?? data['latitude'] as num?;
          num? lng = lastIn?['longitude'] as num? ?? data['longitude'] as num?;
          if (lat == null || lng == null) {
            final college = await getCollegeDetails();
            if (college != null) {
              lat = college['latitude'] as num?;
              lng = college['longitude'] as num?;
            }
          }
          final outEvent = <String, dynamic>{
            'type': 'check_out',
            'time': midnight.toIso8601String(),
            'confidence': 1.0,
            if (lat != null && lng != null) 'latitude': lat.toDouble(),
            if (lat != null && lng != null) 'longitude': lng.toDouble(),
          };
          events.add(outEvent);

          final updatePayload = <String, dynamic>{
            'events': events,
            'checkoutTime': midnight.toIso8601String(),
            'checkoutConfidence': 1.0,
            'autoCheckedOut': true,
            'type': 'check_out',
            'updatedAt': TrueTimeService.now().toIso8601String(),
          };
          if (lat != null && lng != null) {
            updatePayload['latitude'] = lat.toDouble();
            updatePayload['longitude'] = lng.toDouble();
          }
          await doc.reference.update(updatePayload);
        }
      }
    } catch (e) {
      // print('Error in auto-checkout: $e');
    }
  }

  /// Get today's attendance record for a user (if exists)
  Future<DocumentSnapshot?> _getTodayRecord(String userId) async {
    try {
      final now = TrueTimeService.now();
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
            if (recordTime.isAfter(todayStart) &&
                recordTime.isBefore(todayEnd)) {
              return doc;
            }
          } catch (e) {
            // Skip invalid timestamps
          }
        }
      }
      return null;
    } catch (e) {
      // print('Error getting today\'s record: $e');
      return null;
    }
  }

  Future<void> markAttendance({
    required Person person,
    required String type, // 'check_in' or 'check_out'
    required double confidence,
    required String verificationPhotoUrl,
  }) async {
    await init();
    if (_attendanceBox == null) {
      throw Exception('Local attendance storage is only available on Android.');
    }
    final trimmedPhoto = verificationPhotoUrl.trim();
    if (trimmedPhoto.isEmpty) {
      throw Exception('Attendance photo URL is required.');
    }
    final timestamp = TrueTimeService.now();

    // Validate Check-in/Check-out pairing logic
    // We need to check existing records to ensure proper sequence
    final user = await _authService.getCurrentUser();
    if (user != null) {
      final todayRecord = await _getTodayRecord(user.uid);

      String? lastStatus;
      if (todayRecord != null) {
        final data = todayRecord.data() as Map<String, dynamic>?;
        if (data != null) {
          final events = List<Map<String, dynamic>>.from(
            (data['events'] as List?)?.map(
                  (e) => Map<String, dynamic>.from(e as Map),
                ) ??
                [],
          );

          if (events.isNotEmpty) {
            events.sort(
              (a, b) => (a['time'] as String).compareTo(b['time'] as String),
            );
            lastStatus = events.last['type'] as String?;
          } else if (data['checkInTime'] != null) {
            // Fallback for old format
            lastStatus = data['checkoutTime'] == null
                ? 'check_in'
                : 'check_out';
          }
        }
      }

      // Enforce the rules
      if (type == 'check_in') {
        if (lastStatus == 'check_in') {
          throw Exception(
            'You are already checked in! Please check out first.',
          );
        }
      } else if (type == 'check_out') {
        if (lastStatus == 'check_out') {
          throw Exception('You are already checked out.');
        }
      }
    }

    final position = await _locationService.getLocationForAttendanceSnapshot();
    if (position == null) {
      throw Exception(
        'Could not capture your location. Enable location permission and GPS, then try again.',
      );
    }

    // Save to local storage immediately so UI can pop and feel instant
    final record = AttendanceRecord(
      personId: person.id,
      personName: person.name,
      employeeId: person.employeeId,
      timestamp: timestamp,
      confidence: confidence,
      type: type,
      synced: false,
      photoUrl: trimmedPhoto,
      latitude: position.latitude,
      longitude: position.longitude,
    );
    await _attendanceBox!.add(record);
    await record.save();

    // Sync to Firebase in background (don't block UI)
    final isConnected = await _connectivityService.isConnected();
    if (isConnected) {
      unawaited(
        _syncAttendanceToFirebaseInBackground(
          person: person,
          type: type,
          confidence: confidence,
          timestamp: timestamp,
          localRecord: record,
        ),
      );
    }
  }

  /// Ensures [localRecord] has coordinates (fills from GPS if missing — e.g. legacy rows).
  Future<bool> _ensureLatLngOnRecord(AttendanceRecord localRecord) async {
    if (localRecord.latitude != null && localRecord.longitude != null) {
      return true;
    }
    final p = await _locationService.getLocationForAttendanceSnapshot();
    if (p == null) return false;
    localRecord.latitude = p.latitude;
    localRecord.longitude = p.longitude;
    await localRecord.save();
    return true;
  }

  /// Sync a single attendance record to Firebase in background.
  /// Called after saving locally so the UI can pop immediately.
  Future<void> _syncAttendanceToFirebaseInBackground({
    required Person person,
    required String type,
    required double confidence,
    required DateTime timestamp,
    required AttendanceRecord localRecord,
  }) async {
    final today = DateTime(timestamp.year, timestamp.month, timestamp.day);
    final dateStr = today.toIso8601String().split('T')[0];

    final hasCoords = await _ensureLatLngOnRecord(localRecord);
    if (!hasCoords) {
      return;
    }
    final photo = localRecord.photoUrl?.trim();
    if (photo == null || photo.isEmpty) {
      return;
    }
    final latitude = localRecord.latitude!;
    final longitude = localRecord.longitude!;

    try {
      final user = await _authService.getCurrentUser();
      if (user == null) return;

      final todayRecord = await _getTodayRecord(user.uid);

      if (todayRecord != null) {
        final recordData = todayRecord.data() as Map<String, dynamic>?;
        if (recordData != null) {
          final updateData = <String, dynamic>{};

          // Get current events or initialize empty
          final events = List<Map<String, dynamic>>.from(
            (recordData['events'] as List?)?.map(
                  (e) => Map<String, dynamic>.from(e as Map),
                ) ??
                [],
          );

          // Add new event (all audit fields required for Firestore)
          final newEvent = {
            'type': type,
            'time': timestamp.toIso8601String(),
            'confidence': confidence,
            'latitude': latitude,
            'longitude': longitude,
            'photoUrl': photo,
          };
          events.add(newEvent);

          // Sort events by time to ensure order
          events.sort(
            (a, b) => (a['time'] as String).compareTo(b['time'] as String),
          );

          // Prepare update data
          updateData['events'] = events;

          // Update top-level status fields for backward compatibility and quick lookups
          if (type == 'check_in') {
            updateData['checkInTime'] = timestamp.toIso8601String();
            updateData['checkInConfidence'] = confidence;
            updateData['type'] = 'check_in';
          } else if (type == 'check_out') {
            updateData['checkoutTime'] = timestamp.toIso8601String();
            updateData['checkoutConfidence'] = confidence;
            updateData['type'] = 'check_out';
          }

          updateData['latitude'] = latitude;
          updateData['longitude'] = longitude;
          updateData['time'] = timestamp.toIso8601String();
          updateData['timestamp'] = timestamp.toIso8601String();
          updateData['confidence'] = confidence;
          updateData['photoUrl'] = photo;

          updateData['personName'] = person.name;
          updateData['personId'] = person.id;
          updateData['employeeId'] = person.employeeId;
          updateData['updatedAt'] = timestamp.toIso8601String();

          await todayRecord.reference.update(updateData);
        }
      } else {
        final eventData = {
          'type': type,
          'time': timestamp.toIso8601String(),
          'confidence': confidence,
          'latitude': latitude,
          'longitude': longitude,
          'photoUrl': photo,
        };

        final recordData = {
          'personId': person.id,
          'personName': person.name,
          'employeeId': person.employeeId,
          'userId': user.uid,
          'date': dateStr,
          'timestamp': timestamp.toIso8601String(),
          'time': timestamp.toIso8601String(),
          'confidence': confidence,
          'type': type,
          'events': [eventData],
          if (type == 'check_in') 'checkInTime': timestamp.toIso8601String(),
          if (type == 'check_in') 'checkInConfidence': confidence,
          if (type == 'check_out') 'checkoutTime': timestamp.toIso8601String(),
          if (type == 'check_out') 'checkoutConfidence': confidence,
          'latitude': latitude,
          'longitude': longitude,
          'createdAt': timestamp.toIso8601String(),
          'photoUrl': photo,
        };

        await _firestore.collection('attendance').add(recordData);
      }

      localRecord.synced = true;
      await localRecord.save();
    } catch (e) {
      // print('Error syncing attendance to Firebase in background: $e');
      // Leave localRecord.synced = false; syncPendingAttendance will retry later
    }
  }

  /// Sync all unsynced attendance records to Firebase
  Future<void> syncPendingAttendance() async {
    if (!_useNativeAndroidAttendance() || _attendanceBox == null) return;
    if (_isSyncing || !_isInitialized) return;

    final isConnected = await _connectivityService.isConnected();
    if (!isConnected) {
      // print('No internet connection, skipping sync');
      return;
    }

    _isSyncing = true;
    try {
      final user = await _authService.getCurrentUser();
      if (user == null) {
        _isSyncing = false;
        return;
      }

      // Get all unsynced records (handle old records without synced field)
      final unsyncedRecords = _attendanceBox!.values
          .where(
            (record) => record.synced == false && record.employeeId == user.uid,
          )
          .toList();

      // print('Checking ${unsyncedRecords.length} pending attendance records for sync...');

      // Group records by date
      final recordsByDate = <String, List<AttendanceRecord>>{};
      for (var record in unsyncedRecords) {
        final dateStr = DateTime(
          record.timestamp.year,
          record.timestamp.month,
          record.timestamp.day,
        ).toIso8601String().split('T')[0];

        if (!recordsByDate.containsKey(dateStr)) {
          recordsByDate[dateStr] = [];
        }
        recordsByDate[dateStr]!.add(record);
      }

      // int syncedCount = 0;
      // int skippedCount = 0;

      // Process each date's records
      for (var entry in recordsByDate.entries) {
        final dateStr = entry.key;
        final records = entry.value;

        try {
          // Check if today's record exists in Firebase
          final todayRecord = await _getTodayRecord(user.uid);

          if (todayRecord != null) {
            final recordData = todayRecord.data() as Map<String, dynamic>?;
            if (recordData != null && recordData['date'] == dateStr) {
              // Update existing record - merge events
              final existingEvents = List<Map<String, dynamic>>.from(
                (recordData['events'] as List?)?.map(
                      (e) => Map<String, dynamic>.from(e as Map),
                    ) ??
                    [],
              );

              // Sort to ensure order
              if (existingEvents.isNotEmpty) {
                existingEvents.sort(
                  (a, b) =>
                      (a['time'] as String).compareTo(b['time'] as String),
                );
              }

              // Add new events from local storage (sorted by timestamp)
              final sortedRecords = List<AttendanceRecord>.from(records)
                ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

              final mergedSuccessfully = <AttendanceRecord>[];
              for (var record in sortedRecords) {
                final coordsOk = await _ensureLatLngOnRecord(record);
                if (!coordsOk) continue;
                final p = record.photoUrl?.trim();
                if (p == null || p.isEmpty) continue;

                final timeStr = record.timestamp.toIso8601String();
                // Check if event already exists (within 5 seconds to be safe)
                final exists = existingEvents.any((e) {
                  try {
                    final existingTime = DateTime.parse(e['time'] as String);
                    final recordTime = record.timestamp;
                    return e['type'] == record.type &&
                        (existingTime.difference(recordTime).abs().inSeconds <=
                            5);
                  } catch (e) {
                    return false;
                  }
                });

                if (!exists) {
                  existingEvents.add({
                    'type': record.type,
                    'time': timeStr,
                    'confidence': record.confidence,
                    'latitude': record.latitude,
                    'longitude': record.longitude,
                    'photoUrl': p,
                  });
                }
                mergedSuccessfully.add(record);
              }

              // Sort again after adding new events
              existingEvents.sort(
                (a, b) => (a['time'] as String).compareTo(b['time'] as String),
              );

              final lastCheckIn = existingEvents.lastWhere(
                (e) => e['type'] == 'check_in',
                orElse: () => {},
              );
              final lastCheckOut = existingEvents.lastWhere(
                (e) => e['type'] == 'check_out',
                orElse: () => {},
              );

              final updateData = {
                'events': existingEvents,
                'updatedAt': TrueTimeService.now().toIso8601String(),
              };

              if (lastCheckIn.isNotEmpty) {
                updateData['checkInTime'] = lastCheckIn['time'];
                updateData['checkInConfidence'] = lastCheckIn['confidence'];
                updateData['type'] =
                    existingEvents.last['type']; // Current status
              }
              if (lastCheckOut.isNotEmpty) {
                updateData['checkoutTime'] = lastCheckOut['time'];
                updateData['checkoutConfidence'] = lastCheckOut['confidence'];
                updateData['type'] =
                    existingEvents.last['type']; // Current status
              }

              await todayRecord.reference.update(updateData);

              for (var record in mergedSuccessfully) {
                record.synced = true;
                await record.save();
              }
              // syncedCount++;
              continue; // Skip to next date
            }
          }

          // Record doesn't exist, create new one
          {
            // Sort records by timestamp to maintain order
            final sortedRecords = List<AttendanceRecord>.from(records)
              ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

            final events = <Map<String, dynamic>>[];
            final createdSynced = <AttendanceRecord>[];
            for (final r in sortedRecords) {
              final coordsOk = await _ensureLatLngOnRecord(r);
              if (!coordsOk) continue;
              final p = r.photoUrl?.trim();
              if (p == null || p.isEmpty) continue;
              events.add({
                'type': r.type,
                'time': r.timestamp.toIso8601String(),
                'confidence': r.confidence,
                'latitude': r.latitude,
                'longitude': r.longitude,
                'photoUrl': p,
              });
              createdSynced.add(r);
            }
            if (events.isEmpty) {
              continue;
            }

            Map<String, dynamic>? lastCheckIn;
            Map<String, dynamic>? lastCheckOut;

            for (var event in events.reversed) {
              if (lastCheckIn == null && event['type'] == 'check_in') {
                lastCheckIn = event;
              }
              if (lastCheckOut == null && event['type'] == 'check_out') {
                lastCheckOut = event;
              }
              if (lastCheckIn != null && lastCheckOut != null) break;
            }

            final firstR = createdSynced.first;
            final recordData = <String, dynamic>{
              'personId': firstR.personId,
              'personName': firstR.personName,
              'employeeId': firstR.employeeId,
              'userId': user.uid,
              'date': dateStr,
              'timestamp': firstR.timestamp.toIso8601String(),
              'confidence': firstR.confidence,
              'type': firstR.type,
              'events': events,
              'latitude': events.last['latitude'],
              'longitude': events.last['longitude'],
            };

            if (lastCheckIn != null) {
              recordData['checkInTime'] = lastCheckIn['time'];
              recordData['checkInConfidence'] = lastCheckIn['confidence'];
            }
            if (lastCheckOut != null) {
              recordData['checkoutTime'] = lastCheckOut['time'];
              recordData['checkoutConfidence'] = lastCheckOut['confidence'];
            }

            recordData['createdAt'] = TrueTimeService.now().toIso8601String();

            await _firestore.collection('attendance').add(recordData);

            for (var record in createdSynced) {
              record.synced = true;
              await record.save();
            }
            // syncedCount++;
          }
        } catch (e) {
          // print('Error syncing records for date $dateStr: $e');
          // Continue with next date
        }
      }

      // print('Sync completed. $syncedCount date(s) synced, $skippedCount skipped.');
    } catch (e) {
      // print('Error during sync: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Start listening for connectivity changes and auto-sync
  void startAutoSync() {
    _connectivityService.connectivityStream.listen((results) async {
      // Check if any connection type is available (not none)
      final hasConnection =
          results.isNotEmpty && !results.contains(ConnectivityResult.none);

      if (hasConnection) {
        // Internet available, sync pending records
        await syncPendingAttendance();
      }
    });
  }

  /// Firestore may store [photoUrl] as String or another type; normalize for Hive/UI.
  String? _eventPhotoUrl(Map<String, dynamic> map) {
    final v = map['photoUrl'];
    if (v == null) return null;
    if (v is String) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  List<Map<String, dynamic>> _attendanceRecordsToEventMaps(
    List<AttendanceRecord> records,
  ) {
    return records
        .map(
          (r) => {
            'type': r.type,
            'time': r.timestamp.toIso8601String(),
            'confidence': r.confidence,
            if (r.photoUrl != null && r.photoUrl!.isNotEmpty)
              'photoUrl': r.photoUrl,
            if (r.latitude != null && r.longitude != null)
              'latitude': r.latitude,
            if (r.latitude != null && r.longitude != null)
              'longitude': r.longitude,
          },
        )
        .toList();
  }

  /// iOS / non-Android: same Firestore-only event list as before (webview pipeline).
  Future<List<Map<String, dynamic>>> _getAttendanceHistoryIosMaps() async {
    try {
      final user = await _authService.getCurrentUser();
      if (user == null) return [];

      final querySnapshot = await _firestore
          .collection('attendance')
          .where('userId', isEqualTo: user.uid)
          .get();

      final List<Map<String, dynamic>> allEvents = [];

      for (final doc in querySnapshot.docs) {
        final data = doc.data();

        if (data['events'] != null) {
          final eventsList = (data['events'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          allEvents.addAll(eventsList);
        } else if (data['type'] != null && data['timestamp'] != null) {
          allEvents.add({
            'type': data['type'],
            'time': data['timestamp'],
            'confidence': data['confidence'] ?? 1.0,
          });
        }
      }

      allEvents.sort((a, b) {
        try {
          final timeA = DateTime.parse(a['time'] as String);
          final timeB = DateTime.parse(b['time'] as String);
          return timeB.compareTo(timeA);
        } catch (e) {
          return 0;
        }
      });

      return allEvents;
    } catch (e) {
      return [];
    }
  }

  /// Flattened events for [AttendanceScreen] history cards.
  Future<List<Map<String, dynamic>>> getAttendanceHistory() async {
    if (!_useNativeAndroidAttendance()) {
      return _getAttendanceHistoryIosMaps();
    }

    final user = await _authService.getCurrentUser();
    if (user == null) {
      if (!_isInitialized || _attendanceBox == null) return [];
      final local = _attendanceBox!.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return _attendanceRecordsToEventMaps(local);
    }

    final List<AttendanceRecord> records = [];

    try {
      // Use userId — every write sets it; employeeId-only queries miss older/variant docs.
      final firebaseRecords = await _firestore
          .collection('attendance')
          .where('userId', isEqualTo: user.uid)
          .get();

      final firebaseList = <AttendanceRecord>[];

      for (var doc in firebaseRecords.docs) {
        final data = doc.data();

        if (data['events'] != null && data['events'] is List) {
          final events = List<Map<String, dynamic>>.from(
            (data['events'] as List).map(
              (e) => Map<String, dynamic>.from(e as Map),
            ),
          );

          for (var event in events) {
            final type = event['type'] ?? 'check_in';
            final timeStr = event['time'] as String?;
            if (timeStr != null) {
              final lat = event['latitude'];
              final lng = event['longitude'];
              firebaseList.add(
                AttendanceRecord(
                  personId: data['personId'] ?? '',
                  personName: data['personName'] ?? '',
                  employeeId: (data['employeeId'] ?? user.uid).toString(),
                  timestamp: DateTime.parse(timeStr),
                  confidence: (event['confidence'] ?? 0.0).toDouble(),
                  type: type,
                  photoUrl: _eventPhotoUrl(event),
                  latitude: lat is num ? lat.toDouble() : null,
                  longitude: lng is num ? lng.toDouble() : null,
                ),
              );
            }
          }
        } else if (data['timestamp'] != null) {
          final topLat = data['latitude'];
          final topLng = data['longitude'];
          firebaseList.add(
            AttendanceRecord(
              personId: data['personId'] ?? '',
              personName: data['personName'] ?? '',
              employeeId: (data['employeeId'] ?? user.uid).toString(),
              timestamp: DateTime.parse(data['timestamp'] as String),
              confidence: (data['confidence'] ?? 0.0).toDouble(),
              type: data['type'] ?? 'check_in',
              photoUrl: _eventPhotoUrl(data),
              latitude: topLat is num ? topLat.toDouble() : null,
              longitude: topLng is num ? topLng.toDouble() : null,
            ),
          );
        }
      }

      firebaseList.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      records.addAll(firebaseList.take(100));
    } catch (e) {
      // ignore
    }

    if (_isInitialized && _attendanceBox != null) {
      final localRecords = _attendanceBox!.values
          .where((r) => r.employeeId == user.uid)
          .toList();

      for (var localRecord in localRecords) {
        final matchIndex = records.indexWhere((r) {
          final timeDiff = (r.timestamp.difference(
            localRecord.timestamp,
          )).abs();
          return r.employeeId == localRecord.employeeId &&
              r.type == localRecord.type &&
              timeDiff.inSeconds <= 1;
        });
        if (matchIndex < 0) {
          records.add(localRecord);
        } else {
          final remote = records[matchIndex];
          final localHasPhoto =
              localRecord.photoUrl != null &&
              localRecord.photoUrl!.trim().isNotEmpty;
          final remoteMissingPhoto =
              remote.photoUrl == null || remote.photoUrl!.trim().isEmpty;
          if (localHasPhoto && remoteMissingPhoto) {
            records[matchIndex] = localRecord;
          }
        }
      }
    }

    records.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    syncPendingAttendance();

    return _attendanceRecordsToEventMaps(records);
  }

  Future<List<DailyAttendance>> getDailyAttendanceHistory() async {
    if (!_useNativeAndroidAttendance()) {
      final user = await _authService.getCurrentUser();
      if (user == null) return [];
      try {
        final querySnapshot = await _firestore
            .collection('attendance')
            .where('userId', isEqualTo: user.uid)
            .get();

        final dailyRecords = querySnapshot.docs
            .map((doc) => DailyAttendance.fromFirestore(doc.data()))
            .where((d) => d.date.isNotEmpty)
            .toList();
        dailyRecords.sort((a, b) => b.date.compareTo(a.date));
        return dailyRecords;
      } catch (e) {
        return [];
      }
    }

    final user = await _authService.getCurrentUser();
    if (user == null) {
      if (!_isInitialized || _attendanceBox == null) return [];
      final localRecords = _attendanceBox!.values.toList();
      return _groupRecordsByDay(localRecords);
    }

    try {
      final firebaseRecords = await _firestore
          .collection('attendance')
          .where('userId', isEqualTo: user.uid)
          .get();

      final dailyRecords = firebaseRecords.docs
          .map((doc) {
            final data = doc.data();
            if (data['date'] != null) {
              return DailyAttendance.fromFirestore(data);
            }
            return null;
          })
          .whereType<DailyAttendance>()
          .toList();

      dailyRecords.sort((a, b) => b.date.compareTo(a.date));

      return dailyRecords;
    } catch (e) {
      return [];
    }
  }

  List<DailyAttendance> _groupRecordsByDay(List<AttendanceRecord> records) {
    final groups = <String, List<AttendanceRecord>>{};
    for (var record in records) {
      final date = record.timestamp.toIso8601String().split('T')[0];
      if (!groups.containsKey(date)) {
        groups[date] = [];
      }
      groups[date]!.add(record);
    }

    final dailyList = <DailyAttendance>[];
    groups.forEach((date, dayRecords) {
      // Create ad-hoc DailyAttendance from local records
      dayRecords.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final events = dayRecords
          .map(
            (r) => {
              'type': r.type,
              'time': r.timestamp.toIso8601String(),
              'confidence': r.confidence,
              if (r.latitude != null && r.longitude != null)
                'latitude': r.latitude,
              if (r.latitude != null && r.longitude != null)
                'longitude': r.longitude,
            },
          )
          .toList();

      final firstIn = dayRecords.firstWhere(
        (r) => r.type == 'check_in',
        orElse: () => dayRecords.first,
      );
      final lastOut = dayRecords.lastWhere(
        (r) => r.type == 'check_out',
        orElse: () => dayRecords.last,
      );

      dailyList.add(
        DailyAttendance(
          date: date,
          checkInTime: firstIn.type == 'check_in' ? firstIn.timestamp : null,
          checkoutTime: lastOut.type == 'check_out' ? lastOut.timestamp : null,
          events: events,
          isPresent: true,
        ),
      );
    });

    dailyList.sort((a, b) => b.date.compareTo(a.date));
    return dailyList;
  }

  List<AttendanceRecord> getAttendanceByPerson(String personId) {
    if (_attendanceBox == null) return [];
    return _attendanceBox!.values
        .where((record) => record.personId == personId)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  List<Person> getAllPersons() {
    if (_personsBox == null) return [];
    return _personsBox!.values.toList();
  }

  Future<void> deletePerson(String personId) async {
    if (_personsBox == null || _attendanceBox == null) return;
    await _personsBox!.delete(personId);
    // Optionally delete attendance records too
    final records = _attendanceBox!.values
        .where((record) => record.personId == personId)
        .toList();
    for (var record in records) {
      await record.delete();
    }
  }

  Future<void> clearAllData() async {
    if (_personsBox == null || _attendanceBox == null) return;
    await _personsBox!.clear();
    await _attendanceBox!.clear();
  }
}
