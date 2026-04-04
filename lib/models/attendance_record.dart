import 'package:hive/hive.dart';

part 'attendance_record.g.dart';

@HiveType(typeId: 1)
class AttendanceRecord extends HiveObject {
  @HiveField(0)
  String personId;

  @HiveField(1)
  String personName;

  @HiveField(2)
  String employeeId;

  @HiveField(3)
  DateTime timestamp;

  @HiveField(4)
  double confidence;

  @HiveField(5)
  String type; // 'check_in' or 'check_out'

  @HiveField(6)
  bool synced; // Whether this record has been synced to Firebase

  /// Firebase Storage URL for the verification snapshot (Android), optional.
  @HiveField(7)
  String? photoUrl;

  /// GPS at mark time (WGS84). Required for new marks; may be null on legacy rows.
  @HiveField(8)
  double? latitude;

  @HiveField(9)
  double? longitude;

  AttendanceRecord({
    required this.personId,
    required this.personName,
    required this.employeeId,
    required this.timestamp,
    required this.confidence,
    required this.type,
    this.synced = false,
    this.photoUrl,
    this.latitude,
    this.longitude,
  });
}
