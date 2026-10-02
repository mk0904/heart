# HEART Nagaland

> **H**igher **E**ducation **A**dministration & **R**esource **T**racker — Nagaland

A Flutter application built for higher-education institutions in Nagaland to manage attendance, events, projects, circulars, and staff coordination — all powered by Firebase.

---

## 📱 App Info

| Field | Value |
|---|---|
| **Version** | `4.5.1+27` |
| **Bundle ID (Android)** | `com.mk2004.heartnagaland` |
| **App Store (iOS)** | [HEART Nagaland on App Store](https://apps.apple.com/us/app/heart-nagaland/id6752921004) |
| **Play Store (Android)** | [HEART Nagaland on Play Store](https://play.google.com/store/apps/details?id=com.mk2004.heartnagaland) |
| **Dart SDK** | `^3.10.7` |
| **Flutter** | Material 3 |
| **Platforms** | Android, iOS (primary); Web, Linux, macOS, Windows (scaffolded) |

---

## ✨ Features

### 🔐 Authentication
- Email/password sign-up and login
- Password reset via email
- Profile completion flow for new users
- Account deletion with confirmation

### 🏠 Home
- Dashboard with role-aware content
- Activity feed and quick actions
- Inactive account guard — locked features until admin approval

### 📅 Attendance
- **Cloud-based face recognition** via a Python backend (`backend/face_matcher/`)
- Check-in / Check-out with GPS location tagging
- **TrueTime (NTP) sync** to prevent device clock manipulation
- College schedule enforcement (configurable start/end times in Firestore)
- Offline-first with **Hive** local storage and automatic Firestore sync
- Attendance history view with daily summaries

### 📂 Projects
- Browse projects assigned to a college
- Submit progress updates with images and percentage completion
- Review submissions (for admins/principals)
- Project status tracking: `Ongoing`, `Completed`, `On Hold`

### 📣 Circulars
- Receive targeted circulars (filtered by recipient list)
- View attachments and full circular details
- Real-time push notifications on new circulars via Firebase Cloud Functions

### 🔔 Notifications & Invitations
- Invitation management with Accept / Decline actions
- Deep notification details: venue, date, time, location link
- **FCM push notifications** (foreground + background) with a "Mark as Read" quick action
- Persistent notification badge support

### 👥 Colleagues
- Browse staff directory filtered by college
- View colleague profiles and contact details

### 📆 Events
- Create, view, and edit events with images
- Participant counts (male/female breakdown)
- Event status: `upcoming`, `ongoing`, `completed`
- Role-based edit permissions

### 🛠 Account & Support
- Edit profile: photo, personal details, employment info
- Contact Us and Support ticket system
- In-app Terms of Service & Privacy Policy (via WebView)
- Government quarter, pay band, designation fields

### 🔄 Force Update
- Mandatory app update gate driven by Firestore (`config/app_update`)
- Separate minimum versions for iOS and Android (`minVersionIos`, `minVersionAndroid`)

---

## 🗂 Project Structure

```
heart_nagaland_flutter_app/
├── lib/
│   ├── main.dart                    # App entry point, init, auth gate
│   ├── firebase_options.dart        # FlutterFire generated config
│   ├── theme/
│   │   └── app_theme.dart           # Design tokens (colors, spacing, shadows)
│   ├── navigation/
│   │   └── main_tab_navigator.dart  # Bottom tab bar (Home, Attendance, Projects, Circulars, Account)
│   ├── models/
│   │   ├── user_profile.dart
│   │   ├── attendance_record.dart   # Hive model
│   │   ├── attendance_record.g.dart # Generated Hive adapter
│   │   ├── daily_attendance.dart
│   │   ├── person.dart              # Hive model
│   │   └── person.g.dart            # Generated Hive adapter
│   ├── screens/                     # 31 screens
│   │   ├── welcome_screen.dart
│   │   ├── login_screen.dart
│   │   ├── signup_screen.dart
│   │   ├── complete_profile_screen.dart
│   │   ├── home_screen.dart
│   │   ├── attendance_screen.dart
│   │   ├── cloud_mark_attendance_screen.dart
│   │   ├── cloud_register_face_screen.dart
│   │   ├── projects_screen.dart
│   │   ├── project_detail_screen.dart
│   │   ├── project_submission_screen.dart
│   │   ├── review_submissions_screen.dart
│   │   ├── circulars_screen.dart
│   │   ├── circular_detail_screen.dart
│   │   ├── events_screen.dart
│   │   ├── event_detail_screen.dart
│   │   ├── event_form_screen.dart
│   │   ├── invitations_screen.dart
│   │   ├── notifications_screen.dart
│   │   ├── notification_detail_screen.dart
│   │   ├── colleagues_screen.dart
│   │   ├── account_screen.dart
│   │   ├── edit_profile_screen.dart
│   │   ├── support_screen.dart
│   │   ├── ticket_detail_screen.dart
│   │   ├── contact_us_screen.dart
│   │   ├── submit_data_screen.dart
│   │   ├── delete_account_screen.dart
│   │   ├── reset_password_screen.dart
│   │   ├── force_update_screen.dart
│   │   └── web_view_screen.dart     # Terms of Service / Privacy Policy
│   ├── services/
│   │   ├── firebase_auth_service.dart
│   │   ├── firestore_service.dart
│   │   ├── firebase_storage_service.dart
│   │   ├── attendance_service.dart  # Core attendance + face recognition logic
│   │   ├── cloud_face_service.dart  # HTTP client for face backend
│   │   ├── face_detection_service.dart
│   │   ├── notification_service.dart # FCM + flutter_local_notifications
│   │   ├── app_update_service.dart  # Mandatory update gate
│   │   ├── app_permission_service.dart
│   │   ├── connectivity_service.dart
│   │   ├── location_service.dart
│   │   └── true_time_service.dart   # NTP clock sync
│   ├── utils/
│   │   ├── user_friendly_errors.dart
│   │   └── event_edit_policy.dart
│   ├── widgets/
│   │   └── image_full_screen_view.dart
│   ├── FIREBASE_DATA_STRUCTURE.md   # Firestore schema reference
│   └── FIREBASE_USAGE.md            # Service usage patterns
├── functions/
│   └── index.js                     # Firebase Cloud Functions (Node.js)
├── backend/
│   └── face_matcher/                # Python face recognition backend
├── assets/
│   └── images/
│       ├── logo.png
│       ├── icon.png
│       ├── home.png
│       ├── logoBg.png
│       └── splash-image.png
├── android/
├── ios/
├── pubspec.yaml
├── firebase.json
└── SETUP.md
```

---

## 🔥 Firebase Services Used

| Service | Usage |
|---|---|
| **Firebase Auth** | Email/password authentication |
| **Cloud Firestore** | All structured data (users, projects, events, circulars, etc.) |
| **Firebase Storage** | Profile photos, event images |
| **Firebase Messaging (FCM)** | Push notifications |
| **Cloud Functions** | Auto-push on new notification/circular documents |

### Firestore Collections

| Collection | Purpose |
|---|---|
| `users` | Staff profiles, roles, college assignment |
| `colleges` | College master data |
| `projects` | Projects assigned to colleges |
| `submissions` | Project progress submissions with images |
| `events` | Events with participants and images |
| `circulars` | Targeted circulars with attachments |
| `notifications` | Invitations and system notifications |
| `config/app_update` | Force-update minimum version config |

### Cloud Functions (`functions/index.js`)

- **`sendNotificationPush`** — triggered on `notifications/{id}` creation, sends FCM push to recipient(s)
- **`onCircularCreated`** — triggered on `circulars/{id}` creation, sends FCM push to all recipients

---

## 📦 Key Dependencies

| Package | Version | Purpose |
|---|---|---|
| `firebase_core` | `^3.6.0` | Firebase initialization |
| `firebase_auth` | `^5.3.1` | Authentication |
| `cloud_firestore` | `^5.4.3` | Database |
| `firebase_storage` | `^12.3.4` | File storage |
| `firebase_messaging` | `^15.1.3` | FCM push notifications |
| `flutter_local_notifications` | `^18.0.1` | Local notification display |
| `hive` + `hive_flutter` | `^2.2.3` | Offline-first local storage |
| `geolocator` | `^13.0.1` | GPS for attendance |
| `camera` | `^0.10.0+2` | Camera for face capture |
| `google_mlkit_face_detection` | `^0.13.2` | On-device face detection |
| `webview_flutter` | `^4.14.0` | In-app policy pages |
| `ntp` | `^2.0.0` | NTP time sync (anti-tampering) |
| `connectivity_plus` | `^6.1.0` | Network state monitoring |
| `image_picker` | `^1.1.2` | Gallery/camera image selection |
| `permission_handler` | `^11.3.1` | Runtime permissions |
| `shared_preferences` | `^2.3.3` | Lightweight key-value storage |
| `url_launcher` | `^6.3.1` | Open store/web URLs |
| `package_info_plus` | `^8.1.2` | App version for update check |
| `http` | `^1.6.0` | HTTP calls to face backend |

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK (Dart `^3.10.7`)
- Android Studio or Xcode
- A **physical device** (camera & face detection do not work on emulators)
- Firebase project with the services above enabled
- Node.js (for deploying Cloud Functions)

### 1. Clone & Install

```bash
git clone git@github.com:mk0904/heart.git
cd heart
flutter pub get
```

### 2. Generate Hive Adapters

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

This generates:
- `lib/models/person.g.dart`
- `lib/models/attendance_record.g.dart`

### 3. Firebase Setup

Place your `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) into the respective platform folders. The `lib/firebase_options.dart` file is already configured for the project.

### 4. Run the App

```bash
flutter run
```

> ⚠️ **Must run on a physical device.** Camera and ML Kit face detection are not supported on simulators/emulators.

### 5. Deploy Cloud Functions (optional)

```bash
cd functions
npm install
cd ..
firebase deploy --only functions
```

---

## 🧩 Architecture Notes

- **Auth gate** — `main.dart` checks mandatory update → notification init → auth state → routes to `WelcomeScreen`, `CompleteProfileScreen`, or `MainTabNavigator`
- **Inactive account guard** — `MainTabNavigator` accepts `isActive` flag; locked tabs show a full-screen overlay prompting admin approval
- **Attendance anti-tamper** — `TrueTimeService` syncs with NTP pools; attendance timestamps use NTP time, not device clock
- **Offline sync** — `AttendanceService` writes to Hive first, then syncs to Firestore when connectivity is available
- **Face recognition** — ML Kit detects face landmarks on-device; embedding matching is done via the cloud Python backend (`backend/face_matcher/`)
- **Role-based access** — User roles (`principal`, staff, etc.) control visibility of create/edit actions throughout the app

---

## 🎨 Design System

Primary color: `#004D40` (deep teal)  
All design tokens (colors, spacing, border radius, shadows) are defined in `lib/theme/app_theme.dart`.

---

## 📝 License

Private — not published to pub.dev.
