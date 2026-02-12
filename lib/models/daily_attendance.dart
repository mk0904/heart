class DailyAttendance {
  final String date; // YYYY-MM-DD
  final DateTime? checkInTime;
  final DateTime? checkoutTime;
  final List<Map<String, dynamic>> events;
  final bool isPresent;
  final bool autoCheckedOut;
  final double? checkInConfidence;
  final double? checkoutConfidence;

  DailyAttendance({
    required this.date,
    this.checkInTime,
    this.checkoutTime,
    this.events = const [],
    this.isPresent = false,
    this.autoCheckedOut = false,
    this.checkInConfidence,
    this.checkoutConfidence,
  });

  factory DailyAttendance.fromFirestore(Map<String, dynamic> data) {
    final eventsList = List<Map<String, dynamic>>.from(
      (data['events'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? []
    );

    // Sort events by time
    eventsList.sort((a, b) {
      try {
        return (a['time'] as String).compareTo(b['time'] as String);
      } catch (e) {
        return 0;
      }
    });

    DateTime? checkIn;
    DateTime? checkOut;
    
    // Parse times from fields or events
    if (data['checkInTime'] != null) {
      try {
        checkIn = DateTime.parse(data['checkInTime']);
      } catch (e) { /* ignore */ }
    }
    
    if (data['checkoutTime'] != null) {
      try {
        checkOut = DateTime.parse(data['checkoutTime']);
      } catch (e) { /* ignore */ }
    }

    // Fallback to events if top-level fields missing
    if (checkIn == null && eventsList.isNotEmpty) {
      final firstIn = eventsList.firstWhere(
        (e) => e['type'] == 'check_in', 
        orElse: () => {},
      );
      if (firstIn.isNotEmpty) {
        try {
          checkIn = DateTime.parse(firstIn['time']);
        } catch (e) { /* ignore */ }
      }
    }

    if (checkOut == null && eventsList.isNotEmpty) {
      final lastOut = eventsList.lastWhere(
        (e) => e['type'] == 'check_out', 
        orElse: () => {},
      );
      if (lastOut.isNotEmpty) {
        try {
          checkOut = DateTime.parse(lastOut['time']);
        } catch (e) { /* ignore */ }
      }
    }

    return DailyAttendance(
      date: data['date'] ?? '',
      checkInTime: checkIn,
      checkoutTime: checkOut,
      events: eventsList,
      isPresent: checkIn != null,
      autoCheckedOut: data['autoCheckedOut'] ?? false,
      checkInConfidence: (data['checkInConfidence'] as num?)?.toDouble(),
      checkoutConfidence: (data['checkoutConfidence'] as num?)?.toDouble(),
    );
  }
}
