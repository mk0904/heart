import 'dart:async';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/person.dart';
import '../models/attendance_record.dart';
import '../models/daily_attendance.dart';
import 'face_recognition_service.dart';
import 'firebase_auth_service.dart';
import 'firestore_service.dart';
import 'location_service.dart';
import 'connectivity_service.dart';

class AttendanceService {
  static AttendanceService? _instance;
  late Box<Person> _personsBox;
  late Box<AttendanceRecord> _attendanceBox;
  final FaceRecognitionService _faceRecognitionService = FaceRecognitionService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuthService _authService = FirebaseAuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final LocationService _locationService = LocationService();
  final ConnectivityService _connectivityService = ConnectivityService();
  bool _isInitialized = false;
  bool _isSyncing = false;
  Timer? _autoCheckoutTimer;

  // Threshold for face recognition (Euclidean distance)
  // Lower threshold = stricter matching
  // Typical values: 0.6-1.2 (1.0 is a good starting point)
  static const double recognitionThreshold = 1.1;

  // Private constructor for singleton
  AttendanceService._internal();

  // Factory constructor returns the singleton instance
  factory AttendanceService() {
    _instance ??= AttendanceService._internal();
    return _instance!;
  }

  Future<void> init() async {
    if (_isInitialized) {
      return; // Already initialized
    }
    
    // Initialize Hive (safe to call multiple times)
    await Hive.initFlutter();

    // Register adapters (after running build_runner)
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(PersonAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(AttendanceRecordAdapter());
    }

    _personsBox = await Hive.openBox<Person>('persons');
    _attendanceBox = await Hive.openBox<AttendanceRecord>('attendance');

    await _faceRecognitionService.loadModel();
    _isInitialized = true;
    
    // Sync current user's face embedding from Firebase to local storage (non-blocking)
    syncCurrentUserEmbedding();
    
    // Check for auto-checkout on initialization (non-blocking)
    checkAutoCheckout();
    
    // Set up periodic auto-checkout (runs every hour)
    _autoCheckoutTimer?.cancel();
    _autoCheckoutTimer = Timer.periodic(const Duration(hours: 1), (timer) {
      checkAutoCheckout();
    });
  }
  
  /// Sync current user's face embedding from Firebase to local storage
  Future<void> syncCurrentUserEmbedding() async {
    try {
      final user = await _authService.getCurrentUser();
      if (user == null) return;
      
      // Check if already exists in local storage
      final existingPerson = _personsBox.get(user.uid);
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
            registeredAt: DateTime.now(),
          );
          
          await _personsBox.put(person.id, person);

          // print('Synced face embedding from Firebase to local storage');
        }
      }
    } catch (e) {
      // print('Error syncing face embedding from Firebase: $e');
      // Non-critical, continue silently
    }
  }

  // Getter to check if service is initialized
  bool get isInitialized => _isInitialized;

  Future<void> registerPerson({
    required String name,
    required String employeeId,
    required List<double> faceEmbedding,
  }) async {
    if (!_isInitialized) {
      throw Exception('AttendanceService not initialized. Call init() first.');
    }
    final person = Person(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      employeeId: employeeId,
      faceEmbedding: faceEmbedding,
      registeredAt: DateTime.now(),
    );

    await _personsBox.put(person.id, person);
  }

  /// Register person with Firebase - stores face embedding in user document
  Future<void> registerPersonWithFirebase({
    required String name,
    required String employeeId,
    required List<double> faceEmbedding,
  }) async {
    // Get current user
    final user = await _authService.getCurrentUser();
    if (user == null) {
      throw Exception('User not authenticated');
    }

    // Store in Firebase user document
    await _firestore.collection('users').doc(user.uid).update({
      'faceEmbedding': faceEmbedding,
      'faceRegisteredAt': DateTime.now().toIso8601String(),
      'faceRegistered': true,
    });

    // Also store locally in Hive for offline recognition
    if (_isInitialized) {
      final person = Person(
        id: user.uid,
        name: name,
        employeeId: employeeId,
        faceEmbedding: faceEmbedding,
        registeredAt: DateTime.now(),
      );
      await _personsBox.put(person.id, person);
    }
  }

  Future<Person?> recognizePerson(List<double> embedding) async {
    if (!_isInitialized) {
      throw Exception('AttendanceService not initialized. Call init() first.');
    }
    
    // Step 1: First check local storage (fast, offline)
    Person? bestMatch;
    double minDistance = double.infinity;

    for (var person in _personsBox.values) {
      final distance = _faceRecognitionService.euclideanDistance(
        embedding,
        person.faceEmbedding,
      );

      if (distance < minDistance && distance < recognitionThreshold) {
        minDistance = distance;
        bestMatch = person;
      }
    }

    // Step 2: If no match found locally, try Firebase fallback
    if (bestMatch == null) {
      try {
        final user = await _authService.getCurrentUser();
        if (user != null) {
          // Fetch user document from Firebase
          final userDoc = await _firestore.collection('users').doc(user.uid).get();
          if (userDoc.exists) {
            final data = userDoc.data();
            final faceEmbedding = data?['faceEmbedding'];
            
            if (faceEmbedding != null && faceEmbedding is List) {
              // Convert to List<double>
              final firebaseEmbedding = faceEmbedding
                  .map((e) => (e as num).toDouble())
                  .toList();
              
              // Compare with Firebase embedding
              final distance = _faceRecognitionService.euclideanDistance(
                embedding,
                firebaseEmbedding,
              );

              if (distance < recognitionThreshold) {
                // Match found in Firebase! Create Person object and sync to local storage
                final person = Person(
                  id: user.uid,
                  name: user.name,
                  employeeId: user.uid,
                  faceEmbedding: firebaseEmbedding,
                  registeredAt: DateTime.now(),
                );
                
                // Sync to local storage for future offline recognition
                await _personsBox.put(person.id, person);
                
                return person;
              }
            }
          }
        }
      } catch (e) {
        // print('Error checking Firebase for face recognition: $e');
        // Continue and return null if Firebase check fails
      }
    }

    return bestMatch;
  }

  /// Check if user is currently checked in (has more check-ins than check-outs today)
  Future<bool> isCurrentlyCheckedIn() async {
    final user = await _authService.getCurrentUser();
    if (user == null) return false;

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    // final dateStr = todayStart.toIso8601String().split('T')[0];

    // Check Firebase first
    try {
      final todayRecord = await _getTodayRecord(user.uid);
      if (todayRecord != null) {
        final data = todayRecord.data() as Map<String, dynamic>?;
        if (data != null) {
          // Check events array (new format)
          final events = List<Map<String, dynamic>>.from(
            (data['events'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? []
          );
          
          // Handle backward compatibility
          if (events.isEmpty) {
            if (data['checkInTime'] != null) {
              events.add({'type': 'check_in', 'time': data['checkInTime'] as String});
            }
            if (data['checkoutTime'] != null) {
              events.add({'type': 'check_out', 'time': data['checkoutTime'] as String});
            }
          }
          
          // User is checked in if last event is check_in
          if (events.isNotEmpty) {
            return events.last['type'] == 'check_in';
          }
        }
      }
    } catch (e) {
      // print('Error checking Firebase attendance: $e');
    }

    // Fallback to local storage (check for check-in without check-out)
    if (!_isInitialized) return false;
    final todayRecords = _attendanceBox.values
        .where((r) => r.employeeId == user.uid &&
               r.timestamp.year == todayStart.year &&
               r.timestamp.month == todayStart.month &&
               r.timestamp.day == todayStart.day)
        .toList();

    if (todayRecords.isNotEmpty) {
      // Count check-ins vs check-outs
      final checkInCount = todayRecords.where((r) => r.type == 'check_in').length;
      final checkOutCount = todayRecords.where((r) => r.type == 'check_out').length;
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

  /// Get college time settings (for backward compatibility)
  Future<Map<String, int>?> getCollegeTimeSettings() async {
    final details = await getCollegeDetails();
    if (details == null) return null;
    return {
      'startHour': details['startTime'] as int,
      'endHour': details['endTime'] as int,
    };
  }

  /// Check if current time is within college hours
  Future<bool> isWithinCollegeHours() async {
    final details = await getCollegeDetails();
    if (details == null) return true; // If no settings, allow anytime

    final now = DateTime.now();
    final currentHour = now.hour;
    final startHourRaw = details['startTime'];
    final endHourRaw = details['endTime'];
    
    // Handle both int and double types
    final startHour = startHourRaw is int ? startHourRaw : (startHourRaw as num).toInt();
    final endHour = endHourRaw is int ? endHourRaw : (endHourRaw as num).toInt();

    return currentHour >= startHour && currentHour < endHour;
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
    // And implicitly less than 24 since currentHour is 0-23
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

  /// Auto-checkout users who haven't checked out by midnight
  /// This checks yesterday's records and auto-checks them out at 11:59 PM
  Future<void> checkAutoCheckout() async {
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      
      // Get yesterday's date
      final yesterday = todayStart.subtract(const Duration(days: 1));
      final yesterdayStr = yesterday.toIso8601String().split('T')[0];
      
      // Find all attendance records for yesterday
      final allRecords = await _firestore
          .collection('attendance')
          .get();
      
      // Filter yesterday's records in memory (to avoid index requirement)
      final yesterdayRecords = allRecords.docs.where((doc) {
        final data = doc.data();
        final dateStr = data['date'] as String?;
        if (dateStr == yesterdayStr) return true;
        
        // Also check timestamp field for backward compatibility
        final timestamp = data['timestamp'] as String?;
        if (timestamp != null) {
          try {
            final recordTime = DateTime.parse(timestamp);
            final recordDate = DateTime(recordTime.year, recordTime.month, recordTime.day);
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
        
        // Get events array (new format)
        final events = List<Map<String, dynamic>>.from(
          (data['events'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? []
        );
        
        // Handle backward compatibility
        if (events.isEmpty) {
          if (data['checkInTime'] != null) {
            events.add({
              'type': 'check_in',
              'time': data['checkInTime'] as String,
              'confidence': (data['checkInConfidence'] as num?)?.toDouble() ?? 0.0,
            });
          }
          if (data['checkoutTime'] != null) {
            events.add({
              'type': 'check_out',
              'time': data['checkoutTime'] as String,
              'confidence': (data['checkoutConfidence'] as num?)?.toDouble() ?? 0.0,
            });
          }
        }
        
        // If last event is check_in, auto-checkout at 11:59 PM
        if (events.isNotEmpty && events.last['type'] == 'check_in') {
          final midnight = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
          events.add({
            'type': 'check_out',
            'time': midnight.toIso8601String(),
            'confidence': 1.0,
          });
          
          await doc.reference.update({
            'events': events,
            'checkoutTime': midnight.toIso8601String(), // backward compat
            'checkoutConfidence': 1.0, // backward compat
            'autoCheckedOut': true,
            'updatedAt': DateTime.now().toIso8601String(),
          });
          // print('Auto-checked out user ${data['userId']} for date $yesterdayStr');
        }
      }
    } catch (e) {
      // print('Error in auto-checkout: $e');
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
      // print('Error getting today\'s record: $e');
      return null;
    }
  }

  Future<void> markAttendance({
    required Person person,
    required String type, // 'check_in' or 'check_out'
    required double confidence,
  }) async {
    final timestamp = DateTime.now();

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
            (data['events'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? []
          );
          
          // Backward compatibility
          if (events.isEmpty) {
            if (data['checkInTime'] != null) {
              events.add({'type': 'check_in', 'time': data['checkInTime'] as String});
            }
            if (data['checkoutTime'] != null) {
              events.add({'type': 'check_out', 'time': data['checkoutTime'] as String});
            }
          }
          
          if (events.isNotEmpty) {
            // Sort by time to be sure
            events.sort((a, b) => (a['time'] as String).compareTo(b['time'] as String));
            lastStatus = events.last['type'] as String?;
          }
        }
      }

      // Enforce the rules
      if (type == 'check_in') {
        if (lastStatus == 'check_in') {
          throw Exception('You are already checked in! Please check out first.');
        }
      } else if (type == 'check_out') {
        if (lastStatus == null || lastStatus == 'check_out') {
          throw Exception('You need to check in first before checking out.');
        }
      }
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
    );
    await _attendanceBox.add(record);
    await record.save();

    // Sync to Firebase in background (don't block UI)
    final isConnected = await _connectivityService.isConnected();
    if (isConnected) {
      unawaited(_syncAttendanceToFirebaseInBackground(
        person: person,
        type: type,
        confidence: confidence,
        timestamp: timestamp,
        localRecord: record,
      ));
    }
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

    double? latitude;
    double? longitude;
    try {
      final position = await _locationService.getCurrentLocation();
      if (position != null) {
        latitude = position.latitude;
        longitude = position.longitude;
      }
    } catch (e) {
      // print('Error getting location in background sync: $e');
    }

    try {
      final user = await _authService.getCurrentUser();
      if (user == null) return;

      final todayRecord = await _getTodayRecord(user.uid);

      if (todayRecord != null) {
        final recordData = todayRecord.data() as Map<String, dynamic>?;
        if (recordData != null) {
          final updateData = <String, dynamic>{};
          final events = List<Map<String, dynamic>>.from(
            (recordData['events'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? []
          );

          if (events.isEmpty) {
            if (recordData['checkInTime'] != null) {
              events.add({
                'type': 'check_in',
                'time': recordData['checkInTime'] as String,
                'confidence': (recordData['checkInConfidence'] as num?)?.toDouble() ?? 0.0,
                if (recordData['latitude'] != null) 'latitude': recordData['latitude'],
                if (recordData['longitude'] != null) 'longitude': recordData['longitude'],
              });
            }
            if (recordData['checkoutTime'] != null) {
              events.add({
                'type': 'check_out',
                'time': recordData['checkoutTime'] as String,
                'confidence': (recordData['checkoutConfidence'] as num?)?.toDouble() ?? 0.0,
                if (recordData['latitude'] != null) 'latitude': recordData['latitude'],
                if (recordData['longitude'] != null) 'longitude': recordData['longitude'],
              });
            }
          }

          final newEvent = {
            'type': type,
            'time': timestamp.toIso8601String(),
            'confidence': confidence,
          };
          if (latitude != null && longitude != null) {
            newEvent['latitude'] = latitude;
            newEvent['longitude'] = longitude;
          }
          events.add(newEvent);

          updateData['events'] = events;
          final lastCheckIn = events.lastWhere((e) => e['type'] == 'check_in', orElse: () => {});
          final lastCheckOut = events.lastWhere((e) => e['type'] == 'check_out', orElse: () => {});

          if (lastCheckIn.isNotEmpty) {
            updateData['checkInTime'] = lastCheckIn['time'];
            updateData['checkInConfidence'] = lastCheckIn['confidence'];
          }
          if (lastCheckOut.isNotEmpty) {
            updateData['checkoutTime'] = lastCheckOut['time'];
            updateData['checkoutConfidence'] = lastCheckOut['confidence'];
          }
          if (latitude != null && longitude != null) {
            updateData['latitude'] = latitude;
            updateData['longitude'] = longitude;
          }
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
        };
        if (latitude != null && longitude != null) {
          eventData['latitude'] = latitude;
          eventData['longitude'] = longitude;
        }

        final recordData = {
          'personId': person.id,
          'personName': person.name,
          'employeeId': person.employeeId,
          'userId': user.uid,
          'date': dateStr,
          'timestamp': timestamp.toIso8601String(),
          'confidence': confidence,
          'type': type,
          'events': [eventData],
          if (type == 'check_in') 'checkInTime': timestamp.toIso8601String(),
          if (type == 'check_in') 'checkInConfidence': confidence,
          if (type == 'check_out') 'checkoutTime': timestamp.toIso8601String(),
          if (type == 'check_out') 'checkoutConfidence': confidence,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
          'createdAt': timestamp.toIso8601String(),
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
      final unsyncedRecords = _attendanceBox.values
          .where((record) => 
            record.synced == false && 
            record.employeeId == user.uid
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
                (recordData['events'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? []
              );
              
              // Handle backward compatibility
              if (existingEvents.isEmpty) {
                if (recordData['checkInTime'] != null) {
                  existingEvents.add({
                    'type': 'check_in',
                    'time': recordData['checkInTime'] as String,
                    'confidence': (recordData['checkInConfidence'] as num?)?.toDouble() ?? 0.0,
                  });
                }
                if (recordData['checkoutTime'] != null) {
                  existingEvents.add({
                    'type': 'check_out',
                    'time': recordData['checkoutTime'] as String,
                    'confidence': (recordData['checkoutConfidence'] as num?)?.toDouble() ?? 0.0,
                  });
                }
              }
              
              // Add new events from local storage (sorted by timestamp)
              final sortedRecords = List<AttendanceRecord>.from(records)
                ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
              
              for (var record in sortedRecords) {
                final timeStr = record.timestamp.toIso8601String();
                // Check if event already exists (within 2 seconds)
                final exists = existingEvents.any((e) {
                  try {
                    final existingTime = DateTime.parse(e['time'] as String);
                    final recordTime = record.timestamp;
                    return e['type'] == record.type && 
                           (existingTime.difference(recordTime).abs().inSeconds <= 2);
                  } catch (e) {
                    return false;
                  }
                });
                
                if (!exists) {
                  existingEvents.add({
                    'type': record.type,
                    'time': timeStr,
                    'confidence': record.confidence,
                  });
                }
              }
              
              // Sort events by time
              existingEvents.sort((a, b) {
                try {
                  return DateTime.parse(a['time'] as String)
                      .compareTo(DateTime.parse(b['time'] as String));
                } catch (e) {
                  return 0;
                }
              });
              
              Map<String, dynamic>? lastCheckIn;
              Map<String, dynamic>? lastCheckOut;
              
              for (var event in existingEvents.reversed) {
                if (lastCheckIn == null && event['type'] == 'check_in') {
                  lastCheckIn = event;
                }
                if (lastCheckOut == null && event['type'] == 'check_out') {
                  lastCheckOut = event;
                }
                if (lastCheckIn != null && lastCheckOut != null) break;
              }
              
              final updateData = <String, dynamic>{
                'events': existingEvents,
                'personName': records.first.personName,
                'updatedAt': DateTime.now().toIso8601String(),
              };
              
              // Backward compatibility
              if (lastCheckIn != null) {
                updateData['checkInTime'] = lastCheckIn['time'];
                updateData['checkInConfidence'] = lastCheckIn['confidence'];
              }
              if (lastCheckOut != null) {
                updateData['checkoutTime'] = lastCheckOut['time'];
                updateData['checkoutConfidence'] = lastCheckOut['confidence'];
              }
              
              await todayRecord.reference.update(updateData);
              
              // Mark all records for this date as synced
              for (var record in records) {
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
            
            final events = sortedRecords.map((r) => <String, dynamic>{
              'type': r.type,
              'time': r.timestamp.toIso8601String(),
              'confidence': r.confidence,
            }).toList();
            
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
            
            final recordData = <String, dynamic>{
              'personId': records.first.personId,
              'personName': records.first.personName,
              'employeeId': records.first.employeeId,
              'userId': user.uid,
              'date': dateStr,
              'timestamp': records.first.timestamp.toIso8601String(),
              'confidence': records.first.confidence,
              'type': records.first.type,
              'events': events,
              // Backward compatibility
            };
            
            if (lastCheckIn != null) {
              recordData['checkInTime'] = lastCheckIn['time'];
              recordData['checkInConfidence'] = lastCheckIn['confidence'];
            }
            if (lastCheckOut != null) {
              recordData['checkoutTime'] = lastCheckOut['time'];
              recordData['checkoutConfidence'] = lastCheckOut['confidence'];
            }
            
            recordData['createdAt'] = DateTime.now().toIso8601String();
            
            await _firestore.collection('attendance').add(recordData);
            
            // Mark all records for this date as synced
            for (var record in records) {
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
      final hasConnection = results.isNotEmpty && 
          !results.contains(ConnectivityResult.none);
      
      if (hasConnection) {
        // Internet available, sync pending records
        await syncPendingAttendance();
      }
    });
  }

  /// Get attendance history from Firebase and local storage
  Future<List<AttendanceRecord>> getAttendanceHistory() async {
    final user = await _authService.getCurrentUser();
    if (user == null) {
      // Fallback to local only
      if (!_isInitialized) return [];
      return _attendanceBox.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }

    final List<AttendanceRecord> records = [];

    // Fetch from Firebase - use employeeId instead of userId to avoid index requirement
    try {
      final firebaseRecords = await _firestore
          .collection('attendance')
          .where('employeeId', isEqualTo: user.uid)
          .get();

      // Convert and sort in memory
      final firebaseList = <AttendanceRecord>[];
      
      for (var doc in firebaseRecords.docs) {
        final data = doc.data();
        
        // Check for 'events' array (support multiple check-ins/outs per day)
        if (data['events'] != null && data['events'] is List) {
          final events = List<Map<String, dynamic>>.from(
            (data['events'] as List).map((e) => Map<String, dynamic>.from(e as Map))
          );
          
          for (var event in events) {
            final type = event['type'] ?? 'check_in';
            final timeStr = event['time'] as String?;
            if (timeStr != null) {
              firebaseList.add(AttendanceRecord(
                personId: data['personId'] ?? '',
                personName: data['personName'] ?? '',
                employeeId: data['employeeId'] ?? '',
                timestamp: DateTime.parse(timeStr),
                confidence: (event['confidence'] ?? 0.0).toDouble(),
                type: type,
              ));
            }
          }
        } else {
          // Backward compatibility: use top-level fields
          firebaseList.add(AttendanceRecord(
            personId: data['personId'] ?? '',
            personName: data['personName'] ?? '',
            employeeId: data['employeeId'] ?? '',
            timestamp: DateTime.parse(data['timestamp']),
            confidence: (data['confidence'] ?? 0.0).toDouble(),
            type: data['type'] ?? 'check_in',
          ));
        }
      }

      // Sort by timestamp descending
      firebaseList.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      records.addAll(firebaseList.take(100)); // Limit to 100 most recent
    } catch (e) {
      // print('Error fetching attendance from Firebase: $e');
    }

    // Merge with local records (avoid duplicates)
    if (_isInitialized) {
      final localRecords = _attendanceBox.values
          .where((r) => r.employeeId == user.uid)
          .toList();
      
      for (var localRecord in localRecords) {
        // Check if not already in Firebase records (match by employeeId, type, and timestamp within 1 second)
        final exists = records.any((r) {
          final timeDiff = (r.timestamp.difference(localRecord.timestamp)).abs();
          return r.employeeId == localRecord.employeeId &&
                 r.type == localRecord.type &&
                 timeDiff.inSeconds <= 1;
        });
        if (!exists) {
          records.add(localRecord);
        }
      }
    }

    records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    // Trigger sync in background (don't wait for it)
    syncPendingAttendance();
    
    return records;
  }

  /// Get daily attendance history (grouped by day)
  Future<List<DailyAttendance>> getDailyAttendanceHistory() async {
    final user = await _authService.getCurrentUser();
    if (user == null) {
      if (!_isInitialized) return [];
      // Group local records for offline caching support
      final localRecords = _attendanceBox.values.toList();
      return _groupRecordsByDay(localRecords);
    }

    try {
      // Fetch from Firebase
      final firebaseRecords = await _firestore
          .collection('attendance')
          .where('userId', isEqualTo: user.uid) // Use userId for daily records
          .get();

      final dailyRecords = firebaseRecords.docs.map((doc) {
        final data = doc.data();
        if (data['date'] != null) {
          return DailyAttendance.fromFirestore(data);
        }
         // Fallback for old records without 'date' field
         // This logic is slightly complex as it requires grouping manually
         // We'll skip legacy handling for now as new records have 'date'
         return null;
      }).whereType<DailyAttendance>().toList();

      dailyRecords.sort((a, b) => b.date.compareTo(a.date));
      
      return dailyRecords;
    } catch (e) {
      // print('Error fetching daily attendance: $e');
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
        final events = dayRecords.map((r) => {
          'type': r.type,
          'time': r.timestamp.toIso8601String(),
          'confidence': r.confidence,
        }).toList();

        final firstIn = dayRecords.firstWhere((r) => r.type == 'check_in', orElse: () => dayRecords.first);
        final lastOut = dayRecords.lastWhere((r) => r.type == 'check_out', orElse: () => dayRecords.last);
        
        dailyList.add(DailyAttendance(
          date: date,
          checkInTime: firstIn.type == 'check_in' ? firstIn.timestamp : null,
          checkoutTime: lastOut.type == 'check_out' ? lastOut.timestamp : null,
          events: events,
          isPresent: true,
        ));
      });

      dailyList.sort((a, b) => b.date.compareTo(a.date));
      return dailyList;
  }

  List<AttendanceRecord> getAttendanceByPerson(String personId) {
    return _attendanceBox.values
        .where((record) => record.personId == personId)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  List<Person> getAllPersons() {
    return _personsBox.values.toList();
  }

  Future<void> deletePerson(String personId) async {
    await _personsBox.delete(personId);
    // Optionally delete attendance records too
    final records = _attendanceBox.values
        .where((record) => record.personId == personId)
        .toList();
    for (var record in records) {
      await record.delete();
    }
  }

  Future<void> clearAllData() async {
    await _personsBox.clear();
    await _attendanceBox.clear();
  }
}
