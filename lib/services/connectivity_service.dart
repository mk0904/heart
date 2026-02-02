import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();

  /// Check if device is connected to internet
  Future<bool> isConnected() async {
    try {
      final results = await _connectivity.checkConnectivity();
      // connectivity_plus 6.x returns List<ConnectivityResult>
      return results.isNotEmpty && 
          !results.contains(ConnectivityResult.none) &&
          results.any((result) => result != ConnectivityResult.none);
    } catch (e) {
      return false;
    }
  }

  /// Stream of connectivity changes
  Stream<List<ConnectivityResult>> get connectivityStream => _connectivity.onConnectivityChanged;
}
