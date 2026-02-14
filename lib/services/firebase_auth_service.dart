import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_profile.dart';

class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Sign up a new user with email and password
  Future<UserProfile> signUp({
    required String email,
    required String password,
    required String fullName,
    required String role,
    String? college,
    String? collegeId,
  }) async {
    try {
      // Create user account
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) {
        throw Exception('User creation failed');
      }

      // Create user profile - use collegeId as college field
      final collegeIdValue = collegeId ?? college;
      final userProfile = UserProfile(
        uid: user.uid,
        email: email,
        name: fullName,
        role: role,
        college: collegeIdValue, // Store collegeId in 'college' field
        collegeId: collegeIdValue,
        createdOn: DateTime.now().toIso8601String(),
        active: false,
        status: 'Active',
        profileCompleted: false,
      );

      // Save user profile to Firestore
      final userUid = user.uid;
      await _firestore
          .collection('users')
          .doc(userUid)
          .set(userProfile.toFirestore());

      // Update Firebase Auth display name
      await user.updateDisplayName(fullName);

      return userProfile;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    } catch (e) {
      throw Exception('Failed to sign up: ${e.toString()}');
    }
  }

  /// Sign in with email and password
  Future<UserProfile> signIn(String email, String password) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) {
        throw Exception('User creation failed');
      }

      // Fetch user profile from Firestore
      final userDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        throw Exception('User profile not found');
      }

      final data = userDoc.data();
      if (data == null) {
        throw Exception('User profile data is null');
      }

      return UserProfile.fromFirestore(data, userDoc.id);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    } catch (e) {
      throw Exception('Failed to sign in: ${e.toString()}');
    }
  }

  /// Sign out the current user
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      throw Exception('Failed to sign out: ${e.toString()}');
    }
  }

  /// Get the current authenticated user profile
  Future<UserProfile?> getCurrentUser() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return null;
      }

      final userDoc = await _firestore.collection('users').doc(user.uid).get();

      if (!userDoc.exists) {
        return null;
      }

      final data = userDoc.data();
      if (data == null) {
        return null;
      }

      return UserProfile.fromFirestore(data, userDoc.id);
    } catch (e) {
      throw Exception('Failed to get current user: ${e.toString()}');
    }
  }

  /// Reset password via email
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    } catch (e) {
      throw Exception('Failed to reset password: ${e.toString()}');
    }
  }

  /// Handle Firebase Auth errors and return user-friendly messages
  Exception _handleAuthError(FirebaseAuthException e) {
    String message = 'An error occurred. Please try again.';

    switch (e.code) {
      case 'email-already-in-use':
        message = 'This email is already registered. Please sign in instead.';
        break;
      case 'invalid-email':
        message = 'Invalid email address.';
        break;
      case 'weak-password':
        message = 'Password should be at least 6 characters.';
        break;
      case 'user-not-found':
        message = 'No account found with this email.';
        break;
      case 'wrong-password':
        message = 'Incorrect password.';
        break;
      case 'user-disabled':
        message = 'This account has been disabled.';
        break;
      case 'network-request-failed':
        message = 'Network error. Please check your connection.';
        break;
      default:
        message = e.message ?? message;
    }

    return Exception(message);
  }

  /// Check if the user's profile is complete
  Future<bool> isProfileComplete(String uid) async {
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (!userDoc.exists) return false;
      
      final data = userDoc.data();
      if (data == null) return false;
      
      return data['profileCompleted'] ?? false;
    } catch (e) {
      return false;
    }
  }
}
