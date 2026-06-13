import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class CloudFaceService {
  CloudFaceService({http.Client? client, FirebaseAuth? auth})
    : _client = client ?? http.Client(),
      _auth = auth ?? FirebaseAuth.instance;

  static const String backendUrl = String.fromEnvironment(
    'FACE_BACKEND_URL',
    defaultValue: 'https://heart-face-matcher-333002007969.us-central1.run.app',
  );

  static bool get isConfigured => backendUrl.trim().isNotEmpty;

  final http.Client _client;
  final FirebaseAuth _auth;

  Uri _uri(String path) {
    final base = backendUrl.endsWith('/')
        ? backendUrl.substring(0, backendUrl.length - 1)
        : backendUrl;
    return Uri.parse('$base$path');
  }

  Future<String> _idToken() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Please sign in again.');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw Exception('Could not authenticate request.');
    }
    return token;
  }

  Future<Map<String, dynamic>> registerFace({
    required File faceImageFile,
    required String faceImageUrl,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/register-face'));
    request.headers['Authorization'] = 'Bearer ${await _idToken()}';
    request.fields['face_image_url'] = faceImageUrl;
    request.files.add(
      await http.MultipartFile.fromPath('image', faceImageFile.path),
    );
    return _send(request);
  }

  Future<Map<String, dynamic>> verifyAttendance({
    required File faceImageFile,
    required String type,
    required String dateYyyyMmDd,
    String? verificationPhotoUrl,
    double? latitude,
    double? longitude,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/verify-attendance'));
    request.headers['Authorization'] = 'Bearer ${await _idToken()}';
    request.fields['type'] = type;
    request.fields['date'] = dateYyyyMmDd;
    if (verificationPhotoUrl != null &&
        verificationPhotoUrl.trim().isNotEmpty) {
      request.fields['verification_photo_url'] = verificationPhotoUrl;
    }
    if (latitude != null) request.fields['latitude'] = latitude.toString();
    if (longitude != null) request.fields['longitude'] = longitude.toString();
    request.files.add(
      await http.MultipartFile.fromPath('image', faceImageFile.path),
    );
    return _send(request);
  }

  Future<Map<String, dynamic>> _send(http.MultipartRequest request) async {
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    Map<String, dynamic> body = {};
    if (response.body.isNotEmpty) {
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        body = {'detail': response.body};
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail =
          body['detail'] ?? body['error'] ?? 'Face verification failed.';
      throw Exception(detail.toString());
    }

    return body;
  }
}
