import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/attendance_service.dart';
import 'services/firebase_auth_service.dart';
import 'services/notification_service.dart';
import 'navigation/main_tab_navigator.dart';
import 'screens/welcome_screen.dart';
import 'screens/complete_profile_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();

  // Initialize notification service
  final notificationService = NotificationService();
  await notificationService.initialize();

  final attendanceService = AttendanceService();
  await attendanceService.init();
  
  // Start auto-sync for offline attendance records
  attendanceService.startAutoSync();
  
  // Also sync immediately if online
  attendanceService.syncPendingAttendance();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark, // Black icons for Android
        statusBarBrightness: Brightness.light, // Light status bar for iOS
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: MaterialApp(
        title: 'HEART Nagaland',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        home: const SplashScreen(),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Navigate to AuthWrapper after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const AuthWrapper()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset(
          'assets/images/icon.png',
          width: 250,
          height: 250,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseAuthService _authService = FirebaseAuthService();
  bool _isLoading = true;
  bool _isAuthenticated = false;
  bool _profileCompleted = true;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    _checkAuthState();
    _auth.authStateChanges().listen((user) async {
      if (user != null) {
        await _checkProfileStatus();
      } else {
        setState(() {
          _isAuthenticated = false;
          _isLoading = false;
        });
      }
    });
  }

  Future<void> _checkAuthState() async {
    final user = _auth.currentUser;
    if (user != null) {
      await _checkProfileStatus();
    } else {
      setState(() {
        _isAuthenticated = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _checkProfileStatus() async {
    try {
      final userProfile = await _authService.getCurrentUser();
      if (userProfile != null) {
        // Check if user is active - use only active boolean field
        final active = userProfile.active;
        final isActive = active ?? true; // Default to true if null
        
        setState(() {
          _isAuthenticated = true;
          _profileCompleted = userProfile.profileCompleted ?? true;
          _isActive = isActive;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isAuthenticated = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isAuthenticated = false;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!_isAuthenticated) {
      return const WelcomeScreen();
    }

    // If profile is not completed, redirect to complete profile screen
    if (!_profileCompleted) {
      return const CompleteProfileScreen();
    }

    return MainTabNavigator(isActive: _isActive);
  }
}
