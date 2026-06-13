import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../firebase_options.dart';
import 'firebase_auth_service.dart';
import 'firestore_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("BACKGROUND MESSAGE RECEIVED: \${message.toMap()}");
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  
  // Force display the notification using our local plugin so that it ALWAYS 
  // has the 'Mark as Read' button, even if FCM sends a notification block.
  final service = NotificationService();
  await service._initializeLocalNotifications();
  await service._showRemoteMessageNotification(message);
}

@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse notificationResponse) async {
  if (notificationResponse.actionId == 'mark_read') {
    final payload = notificationResponse.payload;
    if (payload != null) {
      try {
        final data = jsonDecode(payload);
        final id = data['id']?.toString();
        
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        }
        
        User? user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          try {
            user = await FirebaseAuth.instance.authStateChanges().first.timeout(const Duration(seconds: 2));
          } catch (_) {}
        }
        
        if (user != null && id != null) {
          final firestoreService = FirestoreService();
          await firestoreService.markNotificationAsRead(id, user.uid);
          
          // Explicitly cancel the notification from the system tray
          final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
          await flutterLocalNotificationsPlugin.cancel(id.hashCode & 0x7fffffff);
        }
      } catch (e) {
        debugPrint('Error handling background action: $e');
      }
    }
  }
}

class NotificationService {
  factory NotificationService() => _instance;

  NotificationService._internal();

  static final NotificationService _instance = NotificationService._internal();

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
        'heart_notifications',
        'HEART Notifications',
        description: 'Circulars, events, invitations and push notifications',
        importance: Importance.high,
      );

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuthService _authService = FirebaseAuthService();

  bool _initialized = false;
  bool _hasReceivedInitialSnapshot = false;
  String? _currentUserId;
  StreamSubscription<List<Map<String, dynamic>>>? _notificationSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  final Set<String> _shownNotificationIds = <String>{};

  /// Initialize notification service.
  Future<void> initialize() async {
    if (_initialized) return;

    await _initializeLocalNotifications();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _foregroundMessageSubscription =
        FirebaseMessaging.onMessage.listen(_showRemoteMessageNotification);
    _messageOpenedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _handleRemoteMessageOpen,
    );

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleRemoteMessageOpen(initialMessage);
    }

    final user = await _authService.getCurrentUser();
    if (user != null) {
      _currentUserId = user.uid;
      await _loadShownNotificationIds();
      await _syncMessagingToken();
      await _startListening();
    }

    _authService.authStateChanges.listen((user) async {
      if (user != null && user.uid != _currentUserId) {
        _currentUserId = user.uid;
        await _loadShownNotificationIds();
        await _syncMessagingToken();
        _hasReceivedInitialSnapshot = false;
        await _startListening();
      } else if (user == null) {
        _currentUserId = null;
        _shownNotificationIds.clear();
        _hasReceivedInitialSnapshot = false;
        await _notificationSubscription?.cancel();
      }
    });

    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((token) {
      _saveMessagingToken(token);
    });

    _initialized = true;
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          'mark_read_category',
          actions: <DarwinNotificationAction>[
            DarwinNotificationAction.plain('mark_read', 'Mark as Read'),
          ],
        )
      ],
    );
    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(_androidChannel);
  }

  /// Request notification permissions for FCM and local popup notifications.
  Future<bool> requestPermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final androidAllowed =
          await androidPlugin?.requestNotificationsPermission() ?? true;

      final iosPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final iosAllowed =
          await iosPlugin?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          true;

      final fcmAllowed =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (fcmAllowed || androidAllowed || iosAllowed) {
        await _syncMessagingToken();
      }
      return fcmAllowed && androidAllowed && iosAllowed;
    } catch (e) {
      debugPrint('Notification permission error: $e');
      return false;
    }
  }

  Future<void> _startListening() async {
    if (_currentUserId == null) return;

    await _notificationSubscription?.cancel();

    try {
      final stream = _firestoreService.streamAllNotifications(_currentUserId!);
      _notificationSubscription = stream.listen(
        _checkForNewNotifications,
        onError: (error) {
          debugPrint('Error listening to notifications: $error');
        },
      );
    } catch (e) {
      debugPrint('Error setting up notification listener: $e');
    }
  }

  void _checkForNewNotifications(List<Map<String, dynamic>> notifications) {
    final unreadNotifications = notifications.where((notification) {
      return !_isRead(notification);
    }).toList();

    if (!_hasReceivedInitialSnapshot) {
      _shownNotificationIds.addAll(
        unreadNotifications.map(_notificationStableId),
      );
      _persistShownNotificationIds();
      _hasReceivedInitialSnapshot = true;
      return;
    }

    for (final notification in unreadNotifications) {
      final id = _notificationStableId(notification);
      if (_shownNotificationIds.add(id)) {
        _persistShownNotificationIds();
        _showLocalNotification(notification);
      }
    }
  }

  String get _shownPrefsKey => 'shown_notifications_${_currentUserId ?? 'anon'}';

  Future<void> _loadShownNotificationIds() async {
    final prefs = await SharedPreferences.getInstance();
    _shownNotificationIds
      ..clear()
      ..addAll(prefs.getStringList(_shownPrefsKey) ?? const <String>[]);
  }

  Future<void> _persistShownNotificationIds() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = _shownNotificationIds.toList();
    if (ids.length > 300) {
      ids.removeRange(0, ids.length - 300);
      _shownNotificationIds
        ..clear()
        ..addAll(ids);
    }
    await prefs.setStringList(_shownPrefsKey, ids);
  }

  bool _isRead(Map<String, dynamic> notification) {
    final read = notification['read'];
    final readBy = notification['readBy'] as List?;

    if (read == true) return true;
    if (readBy != null && _currentUserId != null) {
      return readBy.contains(_currentUserId);
    }
    return false;
  }

  String _notificationStableId(Map<String, dynamic> notification) {
    final id = notification['id']?.toString();
    if (id != null && id.isNotEmpty) return id;
    final title = notification['title']?.toString() ?? '';
    final message = notification['message']?.toString() ?? '';
    final createdAt = notification['createdAt']?.toString() ?? '';
    return '$title|$message|$createdAt';
  }

  Future<void> _showLocalNotification(Map<String, dynamic> notification) async {
    final title = notification['title']?.toString().trim().isNotEmpty == true
        ? notification['title'].toString()
        : _titleForType(notification['type']?.toString());
    final message =
        notification['message']?.toString() ??
        notification['body']?.toString() ??
        notification['subtitle']?.toString() ??
        '';
    final notificationId = _notificationStableId(notification);

    final androidDetails = AndroidNotificationDetails(
      _androidChannel.id,
      _androidChannel.name,
      channelDescription: _androidChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'mark_read',
          'Mark as Read',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      categoryIdentifier: 'mark_read_category',
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      notificationId.hashCode & 0x7fffffff,
      title,
      message,
      details,
      payload: jsonEncode(notification),
    );
  }

  Future<void> _showRemoteMessageNotification(RemoteMessage message) async {
    final notification = <String, dynamic>{
      'id': message.messageId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      'title': message.notification?.title ?? message.data['title'],
      'message':
          message.notification?.body ??
          message.data['message'] ??
          message.data['body'],
      'type': message.data['type'] ?? 'push',
      ...message.data,
    };

    final id = _notificationStableId(notification);
    if (_shownNotificationIds.add(id)) {
      await _persistShownNotificationIds();
      await _showLocalNotification(notification);
    }
  }

  Future<void> _syncMessagingToken() async {
    if (_currentUserId == null) return;
    try {
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _saveMessagingToken(token);
      }
    } catch (e) {
      debugPrint('FCM token sync warning: $e');
    }
  }

  Future<void> _saveMessagingToken(String token) async {
    final userId = _currentUserId;
    if (userId == null || token.isEmpty) return;
    try {
      await _firestore.collection('users').doc(userId).set({
        'fcmToken': token,
        'fcmTokens': FieldValue.arrayUnion([token]),
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        'notificationPlatform': defaultTargetPlatform.name,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('FCM token save warning: $e');
    }
  }

  String _titleForType(String? type) {
    switch (type?.toLowerCase()) {
      case 'circular':
        return 'New Circular';
      case 'event':
        return 'New Event';
      case 'invitation':
        return 'New Invitation';
      default:
        return 'New Notification';
    }
  }

  void _onNotificationTapped(NotificationResponse response) async {
    if (response.actionId == 'mark_read') {
      final payload = response.payload;
      if (payload != null) {
        try {
          final data = jsonDecode(payload);
          final id = data['id']?.toString();
          if (id != null) {
            await markAsRead(id);
            // Explicitly cancel the notification from the system tray
            await _localNotifications.cancel(id.hashCode & 0x7fffffff);
          }
        } catch (e) {
          debugPrint('Error handling foreground action: $e');
        }
      }
      return;
    }
    // Payload is intentionally preserved for future navigation routing.
  }

  void _handleRemoteMessageOpen(RemoteMessage message) {
    // Reserved for route handling once notification deep links are defined.
  }

  Future<void> markAsRead(String notificationId) async {
    if (_currentUserId == null) return;

    try {
      await _firestoreService.markNotificationAsRead(
        notificationId,
        _currentUserId!,
      );
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  Future<int> getUnreadCount() async {
    if (_currentUserId == null) return 0;

    try {
      return await _firestoreService.getUnreadNotificationCount(_currentUserId!);
    } catch (e) {
      debugPrint('Error getting unread count: $e');
      return 0;
    }
  }

  void dispose() {
    _notificationSubscription?.cancel();
    _foregroundMessageSubscription?.cancel();
    _messageOpenedSubscription?.cancel();
    _tokenRefreshSubscription?.cancel();
  }
}
