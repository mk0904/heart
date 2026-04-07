import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';

/// Remote minimum versions — Firestore document [firestoreDocPath].
///
/// Create this document in Firebase Console (example fields):
/// - `minVersionIos` (string): e.g. `"3.0.0"` — users below this **cannot** use the app
/// - `minVersionAndroid` (string): same for Android
/// - `updateMessage` (string, optional): shown on the force-update screen
///
/// **Firestore rules:** allow public read on this path so the check works **before login**:
/// `match /config/app_update { allow read: if true; allow write: if false; }`
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  static const String firestoreDocPath = 'config/app_update';

  /// HEART Nagaland on the App Store.
  static const String iosStoreUrl =
      'https://apps.apple.com/us/app/heart-nagaland/id6752921004';

  static const String androidStoreUrl =
      'https://play.google.com/store/apps/details?id=com.mk2004.heartnagaland';

  /// Returns whether the user must update before continuing. On fetch errors or missing
  /// config, returns [MandatoryUpdateResult.notRequired] so the app stays usable offline.
  Future<MandatoryUpdateResult> checkMandatoryUpdate() async {
    if (kIsWeb) return MandatoryUpdateResult.notRequired();

    try {
      final snap =
          await FirebaseFirestore.instance.doc(firestoreDocPath).get();
      if (!snap.exists || snap.data() == null) {
        return MandatoryUpdateResult.notRequired();
      }

      final data = snap.data()!;
      final minIos = (data['minVersionIos'] as String?)?.trim();
      final minAndroid = (data['minVersionAndroid'] as String?)?.trim();
      final message = (data['updateMessage'] as String?)?.trim();

      final info = await PackageInfo.fromPlatform();
      final current = _stripBuildSuffix(info.version);

      if (Platform.isIOS) {
        if (minIos == null || minIos.isEmpty) {
          return MandatoryUpdateResult.notRequired();
        }
        if (_compareSemver(current, minIos) < 0) {
          return MandatoryUpdateResult.required(
            message: message ??
                'Please update to the latest version to continue using HEART Nagaland.',
            storeUrl: iosStoreUrl,
          );
        }
      } else if (Platform.isAndroid) {
        if (minAndroid == null || minAndroid.isEmpty) {
          return MandatoryUpdateResult.notRequired();
        }
        if (_compareSemver(current, minAndroid) < 0) {
          return MandatoryUpdateResult.required(
            message: message ??
                'Please update to the latest version to continue using HEART Nagaland.',
            storeUrl: androidStoreUrl,
          );
        }
      }
    } catch (e, st) {
      debugPrint('AppUpdateService: $e\n$st');
    }

    return MandatoryUpdateResult.notRequired();
  }

  static String _stripBuildSuffix(String version) =>
      version.split('+').first.trim();

  /// Negative if a < b, zero if equal, positive if a > b. Expects numeric x.y.z parts.
  static int _compareSemver(String a, String b) {
    final pa = _parseParts(_stripBuildSuffix(a));
    final pb = _parseParts(_stripBuildSuffix(b));
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  static List<int> _parseParts(String v) {
    return v
        .split('.')
        .map((s) => int.tryParse(s.trim()) ?? 0)
        .toList(growable: false);
  }
}

class MandatoryUpdateResult {
  const MandatoryUpdateResult._({
    required this.isRequired,
    this.message = '',
    this.storeUrl = '',
  });

  factory MandatoryUpdateResult.notRequired() =>
      const MandatoryUpdateResult._(isRequired: false);

  factory MandatoryUpdateResult.required({
    required String message,
    required String storeUrl,
  }) =>
      MandatoryUpdateResult._(
        isRequired: true,
        message: message,
        storeUrl: storeUrl,
      );

  final bool isRequired;
  final String message;
  final String storeUrl;
}
