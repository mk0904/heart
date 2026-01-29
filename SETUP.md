# Face Recognition Attendance System - Setup Instructions

## Prerequisites
- Flutter SDK installed
- Android Studio / Xcode for mobile development
- Physical device (camera doesn't work on emulators)

## Setup Steps

### 1. Install Dependencies
```bash
flutter pub get
```

### 2. Generate Hive Adapters
The Hive models need adapters to be generated. Run:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

This will generate:
- `lib/models/person.g.dart`
- `lib/models/attendance_record.g.dart`

### 3. Verify Model File
Make sure the MobileFaceNet model is located at:
```
assets/models/mobilefacenet.tflite
```

### 4. Run the App
```bash
flutter run
```

**Important:** Run on a physical device, not an emulator, as the camera is required.

## Features

### 1. Register Person
- Navigate to "Register Person"
- Enter name and employee ID
- Position face in camera view
- Tap "Capture & Register"
- Face embedding will be stored in local database

### 2. Mark Attendance
- Navigate to "Mark Attendance"
- Select "Check In" or "Check Out"
- Position face in camera view
- Tap "Capture & Mark Attendance"
- System will recognize the face and mark attendance

### 3. View Attendance History
- Navigate to "Attendance History"
- View all attendance records sorted by date/time
- See confidence scores for each recognition

## Technical Details

### Face Recognition Threshold
The recognition threshold is set to `1.0` (Euclidean distance) in `lib/services/attendance_service.dart`. 
- Lower values = stricter matching (fewer false positives, more false negatives)
- Higher values = looser matching (more false positives, fewer false negatives)
- Recommended range: 0.6 - 1.2

### Model Specifications
- **Model**: MobileFaceNet
- **Input Size**: 112x112 pixels
- **Output Size**: 192-dimensional embedding vector
- **Normalization**: L2 normalization applied to embeddings

### Storage
- Uses Hive for local storage
- Data persists between app sessions
- Stored in device's local storage

## Troubleshooting

### Model Not Loading
- Verify `mobilefacenet.tflite` exists in `assets/models/`
- Check `pubspec.yaml` has `assets: - assets/models/`
- Run `flutter clean` and `flutter pub get`

### Camera Not Working
- Ensure camera permissions are granted
- Check AndroidManifest.xml has camera permission
- Check Info.plist has NSCameraUsageDescription (iOS)
- Use a physical device (not emulator)

### Face Not Detected
- Ensure good lighting
- Face should be clearly visible
- Remove obstructions (masks, sunglasses)
- Position face within camera frame

### Person Not Recognized
- Ensure person is registered first
- Try adjusting recognition threshold
- Ensure similar lighting conditions during registration and recognition
- Try registering multiple angles if needed

## File Structure
```
lib/
├── main.dart
├── models/
│   ├── person.dart
│   ├── person.g.dart (generated)
│   ├── attendance_record.dart
│   └── attendance_record.g.dart (generated)
├── services/
│   ├── face_detection_service.dart
│   ├── face_recognition_service.dart
│   └── attendance_service.dart
└── screens/
    ├── home_screen.dart
    ├── register_screen.dart
    ├── mark_attendance_screen.dart
    └── attendance_history_screen.dart
```

## Next Steps
1. Run `flutter pub get`
2. Run `flutter pub run build_runner build --delete-conflicting-outputs`
3. Connect a physical device
4. Run `flutter run`
5. Test registration and attendance marking
