import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';

/// Converts Firebase and other errors into short, safe messages for users.
class UserFriendlyErrors {
  UserFriendlyErrors._();

  static const String defaultMessage =
      'Something went wrong. Please try again in a moment.';

  static const String networkMessage =
      'Connection problem. Check your internet and try again.';

  /// Primary API: pass any error from catch blocks before showing in UI.
  static String message(Object error) {
    if (error is FirebaseAuthException) {
      return _authMessage(error);
    }
    if (error is FirebaseException) {
      return _firebaseCoreMessage(error);
    }
    if (error is PlatformException) {
      return _platformMessage(error);
    }

    final raw = error.toString();
    final cleaned = raw.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();

    if (cleaned.isEmpty) return defaultMessage;

    final lower = cleaned.toLowerCase();
    if (lower.contains('[firebase') ||
        lower.contains('firebaseexception') ||
        lower.contains('cloud_firestore') ||
        lower.contains('firebase_storage')) {
      return _messageFromFirebaseString(cleaned);
    }

    if (_isNetworkLike(lower)) {
      return networkMessage;
    }

    if (cleaned.length < 160 &&
        !_looksTechnical(cleaned) &&
        !lower.contains('firebase')) {
      return cleaned;
    }

    return defaultMessage;
  }

  static bool _isNetworkLike(String lower) {
    return lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('connection refused') ||
        lower.contains('connection reset') ||
        lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('network error') ||
        lower.contains('no address associated');
  }

  static bool _looksTechnical(String s) {
    final lower = s.toLowerCase();
    return lower.contains('platformexception') ||
        lower.contains('error code:') ||
        (s.contains('at ') && s.contains('.dart:')) ||
        s.length > 220;
  }

  static String _messageFromFirebaseString(String s) {
    final lower = s.toLowerCase();
    if (lower.contains('permission-denied')) {
      return 'You don\'t have permission to perform this action.';
    }
    if (lower.contains('unavailable') || lower.contains('deadline-exceeded')) {
      return 'Service is busy. Please try again in a moment.';
    }
    if (lower.contains('unauthenticated')) {
      return 'Please sign in again to continue.';
    }
    if (lower.contains('not-found')) {
      return 'The requested information could not be found.';
    }
    if (_isNetworkLike(lower)) {
      return networkMessage;
    }
    return defaultMessage;
  }

  static String _authMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'This email is already registered. Please sign in instead.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'weak-password':
        return 'Password should be at least 6 characters.';
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'network-request-failed':
        return networkMessage;
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'invalid-credential':
      case 'invalid-verification-code':
      case 'invalid-verification-id':
        return 'Sign-in details are incorrect or expired. Please try again.';
      case 'operation-not-allowed':
        return 'This sign-in method is not available.';
      case 'requires-recent-login':
        return 'Please sign out and sign in again to continue.';
      default:
        return defaultMessage;
    }
  }

  static String _firebaseCoreMessage(FirebaseException e) {
    final plugin = e.plugin;
    if (plugin == 'firebase_storage') {
      switch (e.code) {
        case 'unauthorized':
        case 'unauthenticated':
          return 'You don\'t have permission to upload this file. Please sign in again.';
        case 'canceled':
          return 'Upload was cancelled.';
        case 'quota-exceeded':
          return 'Storage limit reached. Please try again later.';
        case 'object-not-found':
          return 'File not found.';
        case 'retry-limit-exceeded':
          return networkMessage;
        default:
          return defaultMessage;
      }
    }

    switch (e.code) {
      case 'permission-denied':
        return 'You don\'t have permission to perform this action.';
      case 'unavailable':
      case 'deadline-exceeded':
      case 'resource-exhausted':
        return 'Service is busy. Please try again in a moment.';
      case 'unauthenticated':
        return 'Please sign in again to continue.';
      case 'not-found':
        return 'The requested information could not be found.';
      case 'already-exists':
        return 'This already exists.';
      case 'failed-precondition':
        return 'This action can\'t be completed right now. Please try again.';
      case 'aborted':
      case 'cancelled':
        return 'The request was cancelled. Please try again.';
      case 'invalid-argument':
        return 'Something was wrong with the information provided.';
      default:
        final msg = e.message?.toLowerCase() ?? '';
        if (msg.contains('network') || msg.contains('connection')) {
          return networkMessage;
        }
        return defaultMessage;
    }
  }

  static String _platformMessage(PlatformException e) {
    final code = e.code.toLowerCase();
    if (code.contains('photo_access_denied') ||
        code.contains('camera_access_denied') ||
        code.contains('permission')) {
      return 'Photo or camera access was denied. You can enable it in Settings.';
    }
    if (code == 'cancelled' || code == 'canceled') {
      return 'Selection was cancelled.';
    }
    return defaultMessage;
  }
}
