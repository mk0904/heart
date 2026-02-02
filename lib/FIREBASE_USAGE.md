# Firebase Usage Guide

This guide explains how to use Firebase in your Flutter app.

## 📚 Overview

Your app uses Firebase for:
- **Authentication** (`firebase_auth`) - User login/signup
- **Firestore** (`cloud_firestore`) - Database for storing data

## 🔧 Setup Complete

✅ Firebase is initialized in `main.dart`
✅ Configuration files are in place:
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`

## 📦 Services Created

### 1. `FirebaseAuthService` (`lib/services/firebase_auth_service.dart`)

Handles user authentication:

```dart
import '../services/firebase_auth_service.dart';

final authService = FirebaseAuthService();

// Sign up
final user = await authService.signUp(
  email: 'user@example.com',
  password: 'password123',
  fullName: 'John Doe',
  role: 'employee',
  college: 'College Name',
  collegeId: 'college-id',
);

// Sign in
final user = await authService.signIn('user@example.com', 'password123');

// Get current user
final currentUser = await authService.getCurrentUser();

// Sign out
await authService.signOut();

// Reset password
await authService.resetPassword('user@example.com');
```

### 2. `FirestoreService` (`lib/services/firestore_service.dart`)

Handles Firestore database operations:

```dart
import '../services/firestore_service.dart';

final firestoreService = FirestoreService();

// Get projects
final projects = await firestoreService.getProjects(collegeId: 'college-id');

// Stream projects (real-time updates)
firestoreService.streamProjects(collegeId: 'college-id').listen((projects) {
  // Update UI when projects change
});

// Get circulars
final circulars = await firestoreService.getCirculars(userId: 'user-id');

// Get events
final events = await firestoreService.getEvents(collegeId: 'college-id');

// Get users/colleagues
final users = await firestoreService.getUsers(collegeId: 'college-id');

// Get notifications/invitations
final notifications = await firestoreService.getNotifications('user-id');
```

## 📊 Firebase Collections

Your app uses these Firestore collections:

### 1. **users**
- Stores user profiles
- Document ID: User UID
- Fields: `email`, `name`, `role`, `college`, `collegeId`, `active`, `status`, etc.

### 2. **projects**
- Stores project information
- Fields: `name`, `description`, `status`, `collegeId`, `submissionsCount`, etc.

### 3. **submissions**
- Stores project submissions
- Fields: `projectId`, `userId`, `data`, `submittedAt`, etc.

### 4. **circulars**
- Stores circulars/announcements
- Fields: `title`, `message`, `description`, `recipients` (array), `sentDate`, `attachments`, etc.

### 5. **events**
- Stores events
- Fields: `title`, `description`, `startDate`, `endDate`, `venue`, `collegeId`, `images`, etc.

### 6. **notifications**
- Stores invitations/notifications
- Fields: `title`, `message`, `recipientId`, `status` ('pending', 'accepted', 'declined'), `date`, `time`, `venue`, etc.

### 7. **colleges**
- Stores college information
- Fields: `name`, `district`, `location`, `email`, `phone`, etc.

### 8. **enrollmentData**
- Stores enrollment submissions
- Fields: Various enrollment fields

## 🎯 Example: Using Firebase in a Screen

Here's how to update a screen to use Firebase:

```dart
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../services/firebase_auth_service.dart';

class MyScreen extends StatefulWidget {
  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuthService _authService = FirebaseAuthService();
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    
    try {
      // Get current user
      final user = await _authService.getCurrentUser();
      
      // Fetch data from Firebase
      final items = await _firestoreService.getProjects(
        collegeId: user?.collegeId,
      );
      
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator());
    }
    
    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        return ListTile(
          title: Text(item['name'] ?? ''),
          subtitle: Text(item['description'] ?? ''),
        );
      },
    );
  }
}
```

## 🔄 Real-time Updates (Streams)

For real-time updates, use streams:

```dart
StreamSubscription? _subscription;

@override
void initState() {
  super.initState();
  _setupStream();
}

void _setupStream() {
  final user = await _authService.getCurrentUser();
  
  _subscription = _firestoreService
      .streamProjects(collegeId: user?.collegeId)
      .listen((projects) {
    setState(() {
      _projects = projects;
    });
  });
}

@override
void dispose() {
  _subscription?.cancel();
  super.dispose();
}
```

## 🛠️ Common Operations

### Add a Document
```dart
await _firestoreService.addSubmission({
  'projectId': 'project-id',
  'userId': 'user-id',
  'data': {...},
  'submittedAt': FieldValue.serverTimestamp(),
});
```

### Update a Document
```dart
await _firestoreService.updateUser('user-id', {
  'name': 'New Name',
  'updatedAt': FieldValue.serverTimestamp(),
});
```

### Query with Filters
```dart
// Get projects for a specific college
final projects = await _firestoreService.getProjects(
  collegeId: 'college-id',
);

// Get circulars for a specific user
final circulars = await _firestoreService.getCirculars(
  userId: 'user-id',
);
```

## ⚠️ Error Handling

Always wrap Firebase calls in try-catch:

```dart
try {
  final data = await _firestoreService.getProjects();
  // Use data
} catch (e) {
  // Handle error
  print('Error: $e');
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Error: $e')),
  );
}
```

## 🔐 Security Rules

Make sure your Firestore security rules are set up in Firebase Console:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can read their own profile
    match /users/{userId} {
      allow read: if request.auth != null && request.auth.uid == userId;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Projects - users can read projects for their college
    match /projects/{projectId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && 
        request.auth.token.role == 'admin';
    }
    
    // Add more rules as needed
  }
}
```

## 📝 Next Steps

1. **Update Screens**: Update your screens to use Firebase services
2. **Add Error Handling**: Add proper error handling and loading states
3. **Add Real-time Updates**: Use streams for real-time data updates
4. **Test**: Test all Firebase operations
5. **Set Security Rules**: Configure Firestore security rules in Firebase Console

## 🆘 Troubleshooting

### "Permission denied" errors
- Check Firestore security rules in Firebase Console
- Ensure user is authenticated

### "Collection not found" errors
- Verify collection names match exactly (case-sensitive)
- Check Firebase Console to see if collections exist

### Network errors
- Check internet connection
- Verify Firebase configuration files are correct
- Check Firebase project is active in Firebase Console

## 📚 Resources

- [Firebase Flutter Documentation](https://firebase.flutter.dev/)
- [Cloud Firestore Documentation](https://firebase.google.com/docs/firestore)
- [Firebase Auth Documentation](https://firebase.google.com/docs/auth)
