# HEART Nagaland

**Higher Education Administration & Resource Tracker** — a production Flutter application for institutional workforce management across Nagaland's higher education sector.

![Version](https://img.shields.io/badge/version-4.5.1%2B27-blue)
![Flutter](https://img.shields.io/badge/Flutter-Material%203-02569B?logo=flutter)
![Dart SDK](https://img.shields.io/badge/Dart-%5E3.10.7-0175C2?logo=dart)
![Firebase](https://img.shields.io/badge/Firebase-Firestore%20%7C%20Auth%20%7C%20FCM-FFCA28?logo=firebase)
![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-lightgrey)

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Architecture](#architecture)
3. [Module Breakdown](#module-breakdown)
4. [Firebase Backend](#firebase-backend)
5. [Attendance Subsystem](#attendance-subsystem)
6. [Push Notification Pipeline](#push-notification-pipeline)
7. [Force Update Mechanism](#force-update-mechanism)
8. [Data Models](#data-models)
9. [Dependency Matrix](#dependency-matrix)
10. [Project Structure](#project-structure)
11. [Build & Setup](#build--setup)
12. [Environment Config](#environment-config)

---

## System Overview

HEART is a multi-role, offline-capable mobile platform targeting Android and iOS. It integrates Firebase as its primary backend (Auth, Firestore, Storage, FCM), a Node.js Cloud Functions layer for server-side triggers, and a Python-based face recognition microservice for biometric attendance.

**Core roles:** `principal`, `staff`, `admin`  
**App identifiers:**  
- Android: `com.mk2004.heartnagaland`  
- iOS App Store: `id6752921004`

---

## Architecture

```
┌───────────────────────────────────────────────────────────────┐
│                        Flutter Client                         │
│                                                               │
│  ┌──────────┐  ┌──────────────┐  ┌───────────────────────┐   │
│  │  Screens │  │   Services   │  │        Models         │   │
│  │  (31)    │◄─┤  (12 svcs)   │◄─┤  Hive + Dart classes  │   │
│  └──────────┘  └──────┬───────┘  └───────────────────────┘   │
│                        │                                       │
└────────────────────────┼───────────────────────────────────────┘
                         │
          ┌──────────────┼──────────────────┐
          │              │                  │
    ┌─────▼──────┐ ┌─────▼──────┐  ┌───────▼──────────┐
    │  Firestore │ │  Firebase  │  │  Python Face     │
    │  + Storage │ │  Auth/FCM  │  │  Recognition API │
    └─────┬──────┘ └────────────┘  └──────────────────┘
          │
    ┌─────▼──────────────┐
    │  Cloud Functions   │
    │  (Node.js v2)      │
    │  · sendNotifPush   │
    │  · onCircularCreated│
    └────────────────────┘
```

**Initialization sequence (`main.dart`):**
```
Firebase.initializeApp()
    → AppUpdateService.checkMandatoryUpdate()   // Firestore config/app_update
        → [BLOCKED] ForceUpdateScreen           // if semver < minVersion
    → NotificationService.initialize()          // FCM token registration (non-blocking)
    → AppPermissionService.requestStartup()     // camera, location, notification (non-blocking)
    → AttendanceService.init()                  // Hive box open + Firestore sync (non-blocking, 5s timeout)
    → TrueTimeService.init()                    // NTP pool sync (non-blocking, 5s timeout)
    → FirebaseAuthService.getCurrentUser()      // Firestore users/{uid} fetch
        → WelcomeScreen                         // unauthenticated
        → CompleteProfileScreen                 // profileCompleted == false
        → MainTabNavigator(isActive: bool)      // authenticated + profile complete
```

---

## Module Breakdown

### Navigation

`MainTabNavigator` implements a custom bottom tab bar with **active-state gating**. Users with `active: false` in Firestore are restricted to Home and Account tabs; all other tabs render a lock overlay until admin activation.

Tabs: `Home` · `Attendance` · `Projects` · `Circulars` · `Account`

### Screens (31 total)

| Screen | Key Functionality |
|---|---|
| `welcome_screen` | Entry point, routes to login/signup |
| `login_screen` | Email/password auth via `FirebaseAuthService` |
| `signup_screen` | Registration + FCM token persistence |
| `complete_profile_screen` | Enforced profile gate post-signup |
| `home_screen` | Role-aware dashboard |
| `attendance_screen` | Attendance history, daily summaries |
| `cloud_mark_attendance_screen` | Face capture → cloud biometric verification → Firestore write |
| `cloud_register_face_screen` | Face embedding registration to cloud backend |
| `projects_screen` | College-scoped project list |
| `project_submission_screen` | Progress submission with multi-image upload |
| `review_submissions_screen` | Principal/admin submission review |
| `events_screen` | Event CRUD with role-based edit policy |
| `invitations_screen` | Invitation accept/decline with status sync |
| `notifications_screen` | FCM-backed notification feed |
| `submit_data_screen` | Generic data submission form |
| `support_screen` | Ticket creation and tracking |
| `web_view_screen` | In-app WebView for ToS / Privacy Policy |
| `force_update_screen` | Hard-block update gate with store deep-link |

---

## Firebase Backend

### Firestore Collections & Schema

#### `users/{uid}`
```jsonc
{
  "uid": "string",
  "email": "string",
  "name": "string",
  "role": "principal | staff | admin",
  "college": "string",          // foreign key → colleges/{id}
  "active": "boolean",
  "profileCompleted": "boolean",
  "photoUrl": "string | null",
  "phoneNumber": "string",
  "designation": "string",
  "district": "string",
  "employmentType": "Contractual | Permanent",
  "payBand": "string",
  "govtQuarter": "boolean",
  "dateOfAppointment": "ISO8601",
  "dateOfBirth": "ISO8601",
  "dateOfRetirement": "ISO8601",
  "dateOfConfirmation": "ISO8601",
  "fcmToken": "string",         // single token
  "fcmTokens": ["string"],      // multi-device support
  "createdOn": "ISO8601",
  "updatedAt": "Timestamp"
}
```

#### `projects/{id}`
```jsonc
{
  "id": "string",
  "name": "string",
  "description": "string",
  "status": "Ongoing | Completed | On Hold",
  "collegeId": "string",
  "collegeName": "string",
  "submissionsCount": "number",
  "lastSubmissionDate": "Timestamp",
  "lastSubmissionPercentage": "number"
}
```

#### `submissions/{id}`
```jsonc
{
  "projectId": "string",
  "userId": "string",
  "percentage": "number",
  "notes": "string",
  "images": [{ "url": "string", "publicId": "string", "width": "number", "height": "number", "size": "number" }],
  "createdAt": "Timestamp"
}
```

#### `events/{id}`
```jsonc
{
  "title": "string",
  "status": "upcoming | ongoing | completed",
  "startDate": "YYYY-MM-DD",
  "endDate": "YYYY-MM-DD",
  "venue": "string",
  "district": "string",
  "organizedBy": "string",
  "createdBy": "uid",
  "maleParticipants": "number",
  "femaleParticipants": "number",
  "images": ["url_string"],
  "createdAt": "Timestamp"
}
```

#### `circulars/{id}`
```jsonc
{
  "title": "string",
  "message": "string",
  "recipients": ["uid"],
  "attachments": ["object"],
  "createdAt": "Timestamp"
}
```

#### `notifications/{id}`
```jsonc
{
  "title": "string",
  "message": "string",
  "recipientId": "uid",
  "status": "pending | accepted | declined",
  "type": "invitation | circular | event | push",
  "venue": "string",
  "date": "YYYY-MM-DD",
  "locationLink": "string",
  "createdAt": "Timestamp"
}
```

#### `config/app_update` *(public read, no-write)*
```jsonc
{
  "minVersionIos": "4.5.0",
  "minVersionAndroid": "4.5.0",
  "updateMessage": "string"
}
```

### Firestore Security Rules Note
`config/app_update` must be readable pre-auth:
```
match /config/app_update {
  allow read: if true;
  allow write: if false;
}
```

---

## Attendance Subsystem

The attendance pipeline is the most technically involved module in the app.

```
User taps "Check In"
    │
    ├─► TrueTimeService.now()          // NTP-synced timestamp (anti-tamper)
    ├─► LocationService.getPosition()  // GPS coordinate
    ├─► CameraService.capture()        // Raw image frame
    ├─► FaceDetectionService           // ML Kit on-device face detection
    │       google_mlkit_face_detection v0.13.2
    │
    └─► CloudFaceService.match(image)  // HTTP POST → Python backend
            backend/face_matcher/
            Returns: { matched: bool, confidence: float, personId: string }
                │
                ├─ [MATCH] AttendanceRecord(type: checkIn, timestamp: NTP, location: GPS)
                │           → Hive.put() (immediate, offline-safe)
                │           → FirestoreService.writeAttendance() (async)
                │
                └─ [NO MATCH] Error surfaced via user_friendly_errors.dart
```

### Schedule Enforcement

College schedules are stored in Firestore and parsed by `_parseCollegeScheduleField()`, which handles three timestamp formats:
- `Firestore Timestamp` → converted to local `DateTime`
- `"HH:mm"` 24-hour string
- `"hh:mm AM/PM"` 12-hour string

Attendance outside the configured window is rejected client-side before hitting the network.

### Offline Resilience

`AttendanceService` uses **Hive** (NoSQL embedded key-value store) for all writes. A `ConnectivityService` listener triggers background sync to Firestore when the device comes online. Corrupt Hive boxes are auto-recovered via `_openHiveBoxOrRecreate<T>()`.

---

## Push Notification Pipeline

```
Firestore write: notifications/{id} or circulars/{id}
        │
        ▼
Cloud Function (Node.js Firebase Functions v2)
  sendNotificationPush / onCircularCreated
        │
        ├─► collectRecipientIds()   // resolves recipientId | recipients[]
        ├─► getRecipientTokens()    // batch reads users/{uid}.fcmToken + fcmTokens[]
        └─► messaging.sendEachForMulticast()  // batched in chunks of 500
                │
                ├── android: channelId=heart_notifications, priority=high
                └── apns: sound=default, category=mark_read_category
                        │
                        ▼
                Flutter Client (NotificationService)
                  ├─ Foreground: flutter_local_notifications display
                  ├─ Background: firebaseMessagingBackgroundHandler()
                  └─ Quick action: "Mark as Read" → Firestore status update
```

**FCM token strategy:** The app persists both `fcmToken` (latest) and `fcmTokens[]` (all active devices) to support multi-device users. Cloud Functions resolve tokens from both fields.

---

## Force Update Mechanism

`AppUpdateService` (singleton) compares the installed semver against Firestore-configured minimums using a pure Dart semver comparator — no third-party package dependency.

```dart
_compareSemver(current, minVersion)  // returns negative if update required
```

On update required: app renders `ForceUpdateScreen` with a deep-link to:
- **iOS:** `https://apps.apple.com/us/app/heart-nagaland/id6752921004`
- **Android:** `https://play.google.com/store/apps/details?id=com.mk2004.heartnagaland`

Failure modes (network error, missing Firestore doc) are silently suppressed — the app remains usable.

---

## Data Models

### Hive-persisted (offline storage)

```dart
@HiveType(typeId: 0)
class Person                  // face registration record

@HiveType(typeId: 1)
class AttendanceRecord        // check-in/check-out entry
```

Generated adapters: `person.g.dart`, `attendance_record.g.dart`  
Run `flutter pub run build_runner build --delete-conflicting-outputs` to regenerate.

### Firestore-mapped

```dart
class UserProfile             // users/{uid} document
class DailyAttendance         // aggregated daily view (client-computed)
```

---

## Dependency Matrix

| Package | Version | Justification |
|---|---|---|
| `firebase_core` | `^3.6.0` | Firebase SDK initialization |
| `firebase_auth` | `^5.3.1` | Email/password auth, session management |
| `cloud_firestore` | `^5.4.3` | Primary data store |
| `firebase_storage` | `^12.3.4` | Binary asset storage (images) |
| `firebase_messaging` | `^15.1.3` | FCM token + push delivery |
| `flutter_local_notifications` | `^18.0.1` | Foreground/background notification rendering, action buttons |
| `hive` / `hive_flutter` | `^2.2.3` | Embedded NoSQL, offline-first attendance |
| `hive_generator` + `build_runner` | `^2.0.1` / `^2.4.8` | Hive adapter codegen |
| `geolocator` | `^13.0.1` | GPS coordinates for attendance geo-tagging |
| `camera` | `^0.10.0+2` | Raw camera frame capture for face detection |
| `google_mlkit_face_detection` | `^0.13.2` | On-device face landmark detection |
| `webview_flutter` | `^4.14.0` | In-app WebView for policy documents |
| `ntp` | `^2.0.0` | NTP pool sync — tamper-proof timestamps |
| `connectivity_plus` | `^6.1.0` | Network state stream for offline/online transitions |
| `image_picker` | `^1.1.2` | Camera/gallery image selection for profiles, submissions |
| `permission_handler` | `^11.3.1` | Runtime permissions (camera, location, notifications) |
| `shared_preferences` | `^2.3.3` | Lightweight KV store for session flags |
| `url_launcher` | `^6.3.1` | Deep-links to app stores, external URLs |
| `package_info_plus` | `^8.1.2` | Runtime version resolution for update comparisons |
| `http` | `^1.6.0` | REST calls to Python face recognition backend |
| `image` | `^4.1.1` | Client-side image processing before face submission |
| `flutter_launcher_icons` | `^0.13.1` | Adaptive icon generation (Android + iOS) |

---

## Project Structure

```
.
├── lib/
│   ├── main.dart
│   ├── firebase_options.dart
│   ├── models/
│   │   ├── attendance_record.dart
│   │   ├── attendance_record.g.dart    # generated
│   │   ├── daily_attendance.dart
│   │   ├── person.dart
│   │   ├── person.g.dart               # generated
│   │   └── user_profile.dart
│   ├── navigation/
│   │   └── main_tab_navigator.dart
│   ├── screens/                        # 31 screen widgets
│   ├── services/
│   │   ├── app_permission_service.dart
│   │   ├── app_update_service.dart
│   │   ├── attendance_service.dart     # ~1,559 LOC — core attendance engine
│   │   ├── cloud_face_service.dart
│   │   ├── connectivity_service.dart
│   │   ├── face_detection_service.dart
│   │   ├── firebase_auth_service.dart
│   │   ├── firebase_storage_service.dart
│   │   ├── firestore_service.dart      # ~36K bytes — primary data layer
│   │   ├── location_service.dart
│   │   ├── notification_service.dart   # ~478 LOC — FCM + local notifications
│   │   └── true_time_service.dart
│   ├── theme/
│   │   └── app_theme.dart             # Design token system
│   ├── utils/
│   │   ├── event_edit_policy.dart
│   │   └── user_friendly_errors.dart
│   ├── widgets/
│   │   └── image_full_screen_view.dart
│   ├── FIREBASE_DATA_STRUCTURE.md
│   └── FIREBASE_USAGE.md
├── functions/
│   ├── index.js                        # Cloud Functions v2 (Node.js)
│   └── package.json
├── backend/
│   └── face_matcher/                   # Python face recognition microservice
├── assets/
│   └── images/
│       ├── icon.png                    # Adaptive icon source
│       ├── logo.png
│       ├── logoBg.png
│       ├── home.png
│       └── splash-image.png
├── android/
├── ios/
├── pubspec.yaml
├── firebase.json
├── analysis_options.yaml
└── SETUP.md
```

---

## Build & Setup

### Requirements

- Flutter `>=3.10.7` / Dart `>=3.10.7`
- Xcode 15+ (iOS) / Android Studio (API 21+)
- Physical device required — camera + ML Kit are unsupported on simulators
- Firebase project (Blaze plan for Cloud Functions)
- Node.js `>=18` for function deployment

### Install

```bash
git clone git@github.com:mk0904/heart.git
cd heart
flutter pub get
```

### Codegen (Hive adapters)

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

Generates: `lib/models/person.g.dart`, `lib/models/attendance_record.g.dart`

### Run

```bash
flutter run                        # debug on connected device
flutter run --release              # release build
flutter build apk --release        # Android APK
flutter build ipa                  # iOS archive
```

### Deploy Cloud Functions

```bash
cd functions && npm install && cd ..
firebase deploy --only functions
```

### Regenerate App Icons

```bash
flutter pub run flutter_launcher_icons
```

---

## Environment Config

| Config | Location | Notes |
|---|---|---|
| Firebase options | `lib/firebase_options.dart` | Generated by FlutterFire CLI |
| Android google-services | `android/app/google-services.json` | Not committed |
| iOS plist | `ios/Runner/GoogleService-Info.plist` | Not committed |
| Minimum versions | Firestore `config/app_update` | Runtime, no redeploy needed |
| Face backend URL | `lib/services/cloud_face_service.dart` | Configurable endpoint |
| Attendance threshold | `lib/services/attendance_service.dart` | Euclidean distance, default `1.0` |
| College schedule | Firestore `colleges/{id}` | `startTime`, `endTime` fields |

---

## Design System

All tokens defined in `lib/theme/app_theme.dart`:

| Token | Value |
|---|---|
| Primary | `#004D40` (deep teal) |
| Primary Dark | `#00251A` |
| Secondary | `#005F60` |
| Error | `#FF0000` |
| Success | `#4CAF50` |
| Warning | `#FF9800` |
| Border radius base | `12px` |
| Elevation strategy | Shadow-only, `elevation: 0` on all cards |
| Material version | Material 3 (`useMaterial3: true`) |

---

*Private repository — not published to pub.dev.*
