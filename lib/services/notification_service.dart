import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firestore_service.dart';
import 'firebase_auth_service.dart';

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuthService _authService = FirebaseAuthService();
  
  bool _initialized = false;
  String? _currentUserId;
  StreamSubscription<List<Map<String, dynamic>>>? _notificationSubscription;

  /// Initialize notification service
  Future<void> initialize() async {
    if (_initialized) return;

    // Initialize local notifications
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false, // Don't ask on init
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
    } catch (e) {
      print('Notification init error: $e');
    }

    // Get current user and start listening (works regardless of permissions)
    final user = await _authService.getCurrentUser();
    if (user != null) {
      _currentUserId = user.uid;
      await _startListening();
    }

    // Listen for auth state changes
    _authService.authStateChanges.listen((user) async {
      if (user != null && user.uid != _currentUserId) {
        _currentUserId = user.uid;
        await _startListening();
      } else if (user == null) {
        _currentUserId = null;
        _notificationSubscription?.cancel();
      }
    });

    _initialized = true;
  }

  /// Request notification permissions
  Future<bool> requestPermission() async {
    try {
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
             settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      print('Notification permission error: $e');
      return false;
    }
  }

  /// Start listening for notifications
  Future<void> _startListening() async {
    if (_currentUserId == null) return;

    // Cancel existing subscription
    _notificationSubscription?.cancel();

    // Listen to Firestore notifications in real-time
    try {
      final stream = _firestoreService.streamAllNotifications(_currentUserId!);
      _notificationSubscription = stream.listen(
        (notifications) {
          // Check for new notifications
          _checkForNewNotifications(notifications);
        },
        onError: (error) {
          print('Error listening to notifications: $error');
        },
      );
    } catch (e) {
      print('Error setting up notification listener: $e');
    }
  }

  /// Check for new notifications and show local notifications
  void _checkForNewNotifications(List<Map<String, dynamic>> notifications) {
    // Filter to show only notifications (exclude invitations and circulars)
    final filteredNotifications = notifications.where((notif) {
      final type = notif['type']?.toString().toLowerCase();
      // Only show push notifications or notifications without a type (general notifications)
      // Exclude invitations and circulars
      return type == null || type == 'push' || (type != 'invitation' && type != 'circular');
    }).toList();
    
    // This is a simplified version - in production, you'd want to track
    // which notifications have already been shown
    for (var notification in filteredNotifications) {
      final read = notification['read'];
      final readBy = notification['readBy'] as List?;
      
      // Check if notification is unread
      bool isRead = false;
      if (read == true) {
        isRead = true;
      } else if (readBy != null && readBy.contains(_currentUserId)) {
        isRead = true;
      }
      
      // Show notification if unread
      if (!isRead && _currentUserId != null) {
        _showLocalNotification(notification);
      }
    }
  }

  /// Show local notification
  Future<void> _showLocalNotification(Map<String, dynamic> notification) async {
    final title = notification['title'] ?? 'New Notification';
    final message = notification['message'] ?? '';
    final notificationId = notification['id'] ?? '';

    const androidDetails = AndroidNotificationDetails(
      'notifications',
      'Notifications',
      channelDescription: 'Notifications from HEART Nagaland',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      notificationId.hashCode,
      title,
      message,
      details,
      payload: notificationId,
    );
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    // This will be handled by the app's navigation
    // The payload contains the notification ID
  }

  /// Mark notification as read
  Future<void> markAsRead(String notificationId) async {
    if (_currentUserId == null) return;
    
    try {
      await _firestoreService.markNotificationAsRead(notificationId, _currentUserId!);
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  /// Get unread count
  Future<int> getUnreadCount() async {
    if (_currentUserId == null) return 0;
    
    try {
      return await _firestoreService.getUnreadNotificationCount(_currentUserId!);
    } catch (e) {
      print('Error getting unread count: $e');
      return 0;
    }
  }

  /// Dispose resources
  void dispose() {
    _notificationSubscription?.cancel();
  }
}
