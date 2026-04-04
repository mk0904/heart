# Firebase Data Structure Guide

This document explains how your Firebase data is structured and how to use it in the Flutter app.

## 📊 Collections Overview

### 1. **users** Collection

**Document Structure:**
```dart
{
  'uid': 'QyBuVEjcxBb821z8kZV5xuLTUp72',
  'email': 'testxyz@gmail.com',
  'name': 'Test',
  'role': 'principal',
  'college': 'kjtWPTaCZzbxN3jT3nO9', // This is the collegeId (string)
  'active': true,
  'createdOn': '2026-01-29T05:31:17.026Z', // ISO string
  'updatedAt': Timestamp,
  'profileCompleted': true,
  'photoUrl': null,
  'phone': '',
  'phoneNumber': '8679144515',
  'designation': '',
  'district': '',
  'employmentType': 'Contractual',
  'payBand': 'Pay3',
  'dateOfAppointment': '2026-01-29T05:37:38.579Z',
  'dateOfBirth': '2026-01-29T05:37:38.579Z',
  'dateOfConfirmation': '2026-01-29T05:37:38.579Z',
  'dateOfRetirement': '2026-01-29T05:37:38.579Z',
  'govtQuarter': false,
}
```

**Important Notes:**
- The `college` field contains the college ID (string), not the college name
- Use `college` field to filter users by college
- `collegeId` is an alias that maps to `college` field

**Usage:**
```dart
// Get users from a specific college
final users = await firestoreService.getUsers(
  collegeId: 'kjtWPTaCZzbxN3jT3nO9',
);

// Get current user's collegeId
final user = await authService.getCurrentUser();
final collegeId = user?.college; // This is the college ID
```

### 2. **projects** Collection

**Document Structure:**
```dart
{
  'id': 'mxxv314fcLrI08utKO1E',
  'name': 'Test College Delhi Project',
  'description': 'A basic test project',
  'status': 'Ongoing', // 'Ongoing', 'Completed', 'On Hold'
  'collegeId': '3CENjF5LqpG47yFm9P2i',
  'collegeName': 'Test College Delhi',
  'submissionsCount': 2,
  'lastSubmissionDate': Timestamp,
  'lastSubmissionPercentage': 25,
}
```

**Usage:**
```dart
// Get projects for a college
final projects = await firestoreService.getProjects(
  collegeId: user?.college,
);
```

### 3. **submissions** Collection

**Document Structure:**
```dart
{
  'id': 'Qo0k2yiAGEjcm153e9Zq',
  'projectId': 'mxxv314fcLrI08utKO1E',
  'projectName': 'Test College Delhi Project',
  'userId': 'user123',
  'userName': 'Test User',
  'percentage': 25,
  'notes': 'Erc',
  'images': [
    {
      'url': 'https://res.cloudinary.com/...',
      'publicId': '...',
      'format': 'jpg',
      'width': 1280,
      'height': 1521,
      'size': 222623,
    },
    // ... more images
  ],
  'createdAt': Timestamp,
}
```

**Usage:**
```dart
// Get submissions for a project
final submissions = await firestoreService.getSubmissions('project-id');

// Add a submission
final submissionId = await firestoreService.addSubmission({
  'projectId': 'project-id',
  'userId': 'user-id',
  'userName': 'User Name',
  'projectName': 'Project Name',
  'percentage': 50,
  'notes': 'Notes here',
  'images': [...], // Array of image objects
  'createdAt': FieldValue.serverTimestamp(),
});
```

### 4. **events** Collection

**Document Structure:**
```dart
{
  'id': 'mbFbpPyvom1F7DmslQ6x',
  'title': 'Test Event',
  'description': 'Test Event description',
  'startDate': '2025-09-27',
  'endDate': '2025-09-30',
  'startTime': '11:26 AM',
  'endTime': '11:26 AM',
  'venue': 'Test Venue',
  'organizedBy': 'Manish Kumar',
  'createdBy': 'rjNw0lFr1pMfDObWSLJnA113xTJ3',
  'district': 'Test District',
  'status': 'upcoming', // 'upcoming', 'ongoing', 'completed'
  'maleParticipants': 20,
  'femaleParticipants': 30,
  'images': [
    'https://res.cloudinary.com/...',
    // ... more image URLs
  ],
  'schoolId': null,
  'createdAt': Timestamp,
}
```

**Usage:**
```dart
// Get events (may not have collegeId filter)
final events = await firestoreService.getEvents();
```

### 5. **circulars** Collection

**Document Structure:**
```dart
{
  'id': 'circular-id',
  'title': 'Circular Title',
  'message': 'Circular Message',
  'description': 'Detailed Description',
  'recipients': ['user-id-1', 'user-id-2'], // Array of user IDs
  'sentDate': Timestamp,
  'createdAt': Timestamp,
  'attachments': [...], // Array of attachment objects
}
```

**Usage:**
```dart
// Get circulars for a user
final circulars = await firestoreService.getCirculars(
  userId: user?.uid,
);
```

### 6. **notifications** Collection

**Document Structure:**
```dart
{
  'id': 'notification-id',
  'title': 'Invitation Title',
  'message': 'Invitation Message',
  'subtitle': 'Subtitle',
  'recipientId': 'user-id',
  'status': 'pending', // 'pending', 'accepted', 'declined'
  'date': '2024-01-01',
  'time': '10:00 AM',
  'venue': 'Venue',
  'locationLink': 'https://...',
  'createdAt': Timestamp,
}
```

**Usage:**
```dart
// Get notifications for a user
final notifications = await firestoreService.getNotifications(userId);

// Update notification status
await firestoreService.updateNotificationStatus(
  'notification-id',
  'accepted', // or 'declined'
);
```

### 7. **colleges** Collection

**Document Structure:**
```dart
{
  'id': 'college-id',
  'name': 'College Name',
  'district': 'District Name',
  'location': 'Location',
  'email': 'email@example.com',
  'phone': '1234567890',
  // ... other fields
}
```

## 🔑 Key Points

1. **College ID**: The `college` field in users collection contains the college ID (string), not the name
2. **Filtering**: Always filter users by `college` field, not `collegeId`
3. **Timestamps**: Some fields use ISO strings (`createdOn`), others use Firestore Timestamps (`updatedAt`, `createdAt`)
4. **Arrays**: Images and attachments are stored as arrays
5. **Null Values**: Many fields can be null, always check before using

## 📝 Example: Complete Flow

```dart
// 1. Get current user
final authService = FirebaseAuthService();
final user = await authService.getCurrentUser();

if (user != null) {
  // 2. Get user's college ID
  final collegeId = user.college; // This is the college ID string
  
  // 3. Get projects for that college
  final firestoreService = FirestoreService();
  final projects = await firestoreService.getProjects(
    collegeId: collegeId,
  );
  
  // 4. Get colleagues from same college
  final colleagues = await firestoreService.getUsers(
    collegeId: collegeId,
  );
  
  // 5. Get circulars for the user
  final circulars = await firestoreService.getCirculars(
    userId: user.uid,
  );
  
  // 6. Get notifications
  final notifications = await firestoreService.getNotifications(
    user.uid,
  );
}
```

## 🎯 Common Patterns

### Filter by College
```dart
// Users
final users = await firestoreService.getUsers(
  collegeId: user?.college, // Use 'college' field
);

// Projects
final projects = await firestoreService.getProjects(
  collegeId: user?.college,
);
```

### Handle Timestamps
```dart
// Parse timestamp from Firestore
DateTime? parseTimestamp(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) {
    try {
      return DateTime.parse(value);
    } catch (e) {
      return null;
    }
  }
  // Handle Firestore Timestamp
  try {
    return (value as dynamic).toDate();
  } catch (e) {
    return null;
  }
}
```

### Handle Arrays
```dart
// Images array
final images = data['images'] ?? [];
for (var image in images) {
  final url = image['url'] ?? image; // Could be string or object
  // Use image URL
}
```

## ⚠️ Important Notes

1. **Field Names**: Some fields use different names (e.g., `college` vs `collegeId`)
2. **Data Types**: Be careful with timestamp formats (ISO strings vs Timestamps)
3. **Null Safety**: Always handle null values
4. **Arrays**: Check if arrays exist before iterating
5. **Filtering**: Use correct field names when filtering queries
