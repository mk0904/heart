import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  // Colors
  static const Color primary = Color(0xFF004d40);
  static const Color primaryLight = Color(0xFFA0D9D9);
  static const Color primaryDark = Color(0xFF00251a);
  static const Color secondary = Color(0xFF005F60);
  
  static const Color background = Color(0xFFFFFFFF);
  static const Color backgroundLight = Color(0xFFF8F8F8);
  static const Color backgroundDark = Color(0xFFF5F5F5);
  
  static const Color text = Color(0xFF000000);
  static const Color textSecondary = Color(0xFF666666);
  static const Color textLight = Color(0xFF999999);
  static const Color textDisabled = Color(0xFFCCCCCC);
  
  static const Color border = Color(0xFFCCCCCC);
  static const Color borderLight = Color(0xFFE0E0E0);
  static const Color borderDark = Color(0xFFD0DAD8);
  
  static const Color error = Color(0xFFFF0000);
  static const Color success = Color(0xFF4CAF50);
  static const Color successLight = Color(0xFFE8F5E9);
  static const Color warning = Color(0xFFFF9800);
  static const Color warningLight = Color(0xFFFFF3E0);
  static const Color info = Color(0xFF2196F3);
  
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);

  // Spacing
  static const double spacingXS = 4.0;
  static const double spacingSM = 8.0;
  static const double spacingMD = 12.0;
  static const double spacingBase = 16.0;
  static const double spacingLG = 20.0;
  static const double spacingXL = 24.0;
  static const double spacing2XL = 32.0;
  static const double spacing3XL = 40.0;
  static const double spacing4XL = 48.0;
  static const double spacing5XL = 60.0;

  // Border Radius
  static const double radiusSM = 6.0;
  static const double radiusBase = 12.0;
  static const double radiusLG = 16.0;
  static const double radiusXL = 24.0;
  static const double radiusFull = 9999.0;

  // Shadows - Light shadows for subtle depth and separation
  static List<BoxShadow> shadowSM = [
    BoxShadow(
      color: Colors.black.withOpacity(0.04),
      offset: const Offset(0, 1),
      blurRadius: 2,
    ),
  ];

  static List<BoxShadow> shadowBase = [
    BoxShadow(
      color: Colors.black.withOpacity(0.06),
      offset: const Offset(0, 1),
      blurRadius: 3,
    ),
  ];

  static List<BoxShadow> shadowLG = [
    BoxShadow(
      color: Colors.black.withOpacity(0.08),
      offset: const Offset(0, 2),
      blurRadius: 4,
    ),
  ];

  // Theme Data
  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.light(
        primary: primary,
        secondary: secondary,
        surface: background,
        error: error,
        onPrimary: white,
        onSecondary: white,
        onSurface: text,
        onError: white,
      ),
      scaffoldBackgroundColor: white, // Changed from backgroundLight to white
      appBarTheme: const AppBarTheme(
        backgroundColor: white,
        foregroundColor: text,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      ),
      cardTheme: CardThemeData(
        color: white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusBase),
        ),
      ),
    );
  }
}
