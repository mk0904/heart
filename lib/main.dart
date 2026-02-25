import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/attendance_service.dart';
import 'services/firebase_auth_service.dart';
import 'services/notification_service.dart';
import 'navigation/main_tab_navigator.dart';
import 'screens/welcome_screen.dart';
import 'screens/complete_profile_screen.dart';
import 'theme/app_theme.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.white,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  // Global error handling
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Flutter Error: ${details.exception}');
  };

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Widget? _initialScreen;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final startTime = DateTime.now();
    try {
      // 1. Initialize Firebase
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // 2. Initialize Notification Service (non-blocking)
      NotificationService().initialize().catchError((e) => debugPrint('Notification init warning: $e'));

      // 3. Initialize Attendance Service (non-blocking)
      AttendanceService().init().timeout(const Duration(seconds: 5)).catchError((e) => debugPrint('Attendance init warning: $e'));

      // 4. Check Auth State
      final authService = FirebaseAuthService();
      final userProfile = await authService.getCurrentUser();

      // Calculate how much time is left to reach 2 seconds
      final elapsed = DateTime.now().difference(startTime);
      final remaining = const Duration(seconds: 2) - elapsed;
      if (remaining > Duration.zero) {
        await Future.delayed(remaining);
      }

      if (mounted) {
        setState(() {
          if (userProfile != null) {
            final isComplete = userProfile.profileCompleted ?? false;
            final isActive = userProfile.active ?? true;
            _initialScreen = isComplete 
                ? MainTabNavigator(isActive: isActive) 
                : const CompleteProfileScreen();
          } else {
            _initialScreen = const WelcomeScreen();
          }
          _initialized = true;
        });
      }
    } catch (e) {
      debugPrint('Initialization error: $e');
      
      // Ensure at least 2 seconds even on error
      final elapsed = DateTime.now().difference(startTime);
      final remaining = const Duration(seconds: 2) - elapsed;
      if (remaining > Duration.zero) {
        await Future.delayed(remaining);
      }

      if (mounted) {
        setState(() {
          _initialScreen = const WelcomeScreen();
          _initialized = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: MaterialApp(
        title: 'HEART Nagaland',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        home: _initialized 
            ? _initialScreen 
            : Scaffold(
                backgroundColor: Colors.white,
                body: Center(
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 200,
                    height: 200,
                  ),
                ),
              ),
      ),
    );
  }
}


