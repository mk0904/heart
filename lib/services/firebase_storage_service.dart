import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import '../utils/user_friendly_errors.dart';

class FirebaseStorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Upload a single file to Firebase Storage and return its download URL.
  /// [file] - the local file to upload
  /// [path] - storage path (e.g. 'projects/submissions/abc123/1234567890_0.jpg')
  Future<String> uploadFile(File file, String path) async {
    try {
      final ref = _storage.ref().child(path);
      final contentType = _getContentType(file.path);
      await ref.putFile(
        file,
        SettableMetadata(contentType: contentType),
      );
      return ref.getDownloadURL();
    } catch (e) {
      throw Exception(UserFriendlyErrors.message(e));
    }
  }

  String _getContentType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  /// Upload multiple image files for a project submission.
  /// Returns a list of maps with 'url' and optionally 'name' for each uploaded file.
  Future<List<Map<String, dynamic>>> uploadProjectSubmissionImages({
    required List<File> files,
    required String projectId,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final results = <Map<String, dynamic>>[];

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final ext = _getImageExtension(file.path);
      final storagePath =
          'projects/submissions/$projectId/${timestamp}_$i$ext';

      final url = await uploadFile(file, storagePath);
      results.add({
        'url': url,
        'name': 'image_$i$ext',
      });
    }

    return results;
  }

  String _getImageExtension(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return '.png';
    if (lower.endsWith('.gif')) return '.gif';
    if (lower.endsWith('.webp')) return '.webp';
    return '.jpg';
  }
  /// Upload multiple event images.
  /// Returns a list of download URLs.
  Future<List<String>> uploadEventImages(List<File> files) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final urls = <String>[];

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final ext = _getImageExtension(file.path);
      final path = 'events/${timestamp}_$i$ext';
      
      final url = await uploadFile(file, path);
      urls.add(url);
    }

    return urls;
  }

  /// Upload a user's profile image.
  /// Returns the download URL.
  Future<String> uploadProfileImage(File file, String userId) async {
    final ext = _getImageExtension(file.path);
    final path = 'users/$userId/profile$ext';
    return uploadFile(file, path);
  }

  /// Cropped face used at registration (reference photo for attendance UI).
  Future<String> uploadRegisteredFaceImage(File file, String userId) async {
    final path = 'users/$userId/face_registration.jpg';
    return uploadFile(file, path);
  }

  /// Snapshot from check-in / check-out (Android native camera flow).
  Future<String> uploadAttendanceVerificationImage(
    File file,
    String userId,
    String dateYyyyMmDd,
    String type, // check_in | check_out
  ) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = 'users/$userId/attendance/${dateYyyyMmDd}_${type}_$ts.jpg';
    return uploadFile(file, path);
  }
}
