import 'package:cloud_firestore/cloud_firestore.dart';

const Duration eventEditWindow = Duration(hours: 24);

DateTime? parseEventCreatedAt(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  if (value is Map && value['seconds'] != null) {
    final seconds = (value['seconds'] as num).toInt();
    final nanoseconds = (value['nanoseconds'] as num?)?.toInt() ?? 0;
    return DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000 + nanoseconds ~/ 1000000,
    );
  }
  if (value is String) return DateTime.tryParse(value);
  return null;
}

bool canEditEvent(Map<String, dynamic> event, String? currentUserId) {
  if (currentUserId == null || currentUserId.isEmpty) return false;
  if (event['createdBy']?.toString() != currentUserId) return false;

  final createdAt = parseEventCreatedAt(event['createdAt']);
  if (createdAt == null) return false;

  return DateTime.now().difference(createdAt).compareTo(eventEditWindow) <= 0;
}

DateTime? eventEditableUntil(Map<String, dynamic> event) {
  final createdAt = parseEventCreatedAt(event['createdAt']);
  return createdAt?.add(eventEditWindow);
}
