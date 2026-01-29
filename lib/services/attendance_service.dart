import 'package:hive_flutter/hive_flutter.dart';
import '../models/person.dart';
import '../models/attendance_record.dart';
import 'face_recognition_service.dart';

class AttendanceService {
  static AttendanceService? _instance;
  late Box<Person> _personsBox;
  late Box<AttendanceRecord> _attendanceBox;
  final FaceRecognitionService _faceRecognitionService = FaceRecognitionService();
  bool _isInitialized = false;

  // Threshold for face recognition (Euclidean distance)
  // Lower threshold = stricter matching
  // Typical values: 0.6-1.2 (1.0 is a good starting point)
  static const double recognitionThreshold = 1.0;

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

  Future<Person?> recognizePerson(List<double> embedding) async {
    if (!_isInitialized) {
      throw Exception('AttendanceService not initialized. Call init() first.');
    }
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

    return bestMatch;
  }

  Future<void> markAttendance({
    required Person person,
    required String type, // 'check_in' or 'check_out'
    required double confidence,
  }) async {
    final record = AttendanceRecord(
      personId: person.id,
      personName: person.name,
      employeeId: person.employeeId,
      timestamp: DateTime.now(),
      confidence: confidence,
      type: type,
    );

    await _attendanceBox.add(record);
  }

  List<AttendanceRecord> getAttendanceHistory() {
    if (!_isInitialized) {
      return [];
    }
    return _attendanceBox.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
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
