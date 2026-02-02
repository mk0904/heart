import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class FirebaseStorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Upload a single file to Firebase Storage and return its download URL.
  /// [file] - the local file to upload
  /// [path] - storage path (e.g. 'projects/submissions/abc123/1234567890_0.jpg')
  Future<String> uploadFile(File file, String path) async {
    final ref = _storage.ref().child(path);
    final contentType = _getContentType(file.path);
    await ref.putFile(
      file,
      SettableMetadata(contentType: contentType),
    );
    return ref.getDownloadURL();
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
}
