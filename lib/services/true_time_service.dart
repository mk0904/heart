import 'package:ntp/ntp.dart';

class TrueTimeService {
  static final TrueTimeService _instance = TrueTimeService._internal();

  factory TrueTimeService() => _instance;

  TrueTimeService._internal();

  Duration _offset = Duration.zero;
  bool _isInitialized = false;

  /// Fetch the NTP time and calculate the offset to local device time.
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final ntpTime = await NTP.now();
      final deviceTime = DateTime.now();
      _offset = ntpTime.difference(deviceTime);
      _isInitialized = true;
    } catch (e) {
      // If we cannot connect to the NTP server (e.g. offline), 
      // we fallback to zero offset (local time).
      _offset = Duration.zero;
    }
  }

  /// Returns the actual current time by applying the NTP offset to the device's local time.
  static DateTime now() {
    return DateTime.now().add(_instance._offset);
  }

  /// Forces a sync with the NTP server.
  Future<void> sync() async {
    _isInitialized = false;
    await init();
  }
}
