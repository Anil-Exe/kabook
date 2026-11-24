import 'package:flutter/material.dart';

class AppColors {
  // Metalik / Premium Palette
  static const Color metallicDark = Color(0xFF1A1D21);
  static const Color metallicSilver = Color(0xFFE3E6E8);
  static const Color metallicSurface = Color(0xFFF2F4F0); // Daha sıcak, soft zemin
  static const Color metallicBorder = Color(0xFFE0E0E0);

  // Gradient Colors (Marka)
  static const Color brandBlue = Color(0xFF2E3E18);
  static const Color brandTeal = Color(0xFF4F6628);
  static const Color brandGreen = Color(0xFF374a0f); // İstenen Ana Renk

  // Legacy Support
  static const Color primaryGreen = Color(0xFF374a0f);
  static const Color softGreen = Color(0xFF6B8E23); // Olive Drab
  static const Color cream = Color(0xFFF9FAF7);
  static const Color white = Colors.white;
  static const Color grey = Colors.grey;
  static const Color lightGreenSurface = Color(0xFFECF2E6);

  // Gradient Shader
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF374a0f), Color(0xFF556b2f)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  /// 🌞 LIGHT THEME
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF8F9FA),
    primaryColor: AppColors.brandGreen,
    colorScheme: const ColorScheme.light(
      primary: AppColors.brandGreen,
      secondary: AppColors.brandTeal,
      surface: Colors.white,
      onSurface: AppColors.metallicDark,
      outline: AppColors.metallicBorder,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: AppColors.metallicDark),
      titleTextStyle: TextStyle(
        color: AppColors.metallicDark,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
    ),

    /// ✅ CardThemeData (Flutter 3.35+ FIX)
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(
          color: Color(0xFFEEEEEE),
          width: 1,
        ),
      ),
    ),

    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: AppColors.brandGreen,
      unselectedItemColor: Color(0xFF9E9E9E),
      type: BottomNavigationBarType.fixed,
      elevation: 8,
      showSelectedLabels: false,
      showUnselectedLabels: false,
    ),
    
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF5F5F5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.brandGreen,
      foregroundColor: Colors.white,
      elevation: 4,
      shape: CircleBorder(),
    ),

    textTheme: ThemeData.light().textTheme,
  );

  /// 🌙 DARK THEME
  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0A0A0A),
    primaryColor: AppColors.brandGreen,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.brandGreen,
      secondary: AppColors.brandTeal,
      surface: Color(0xFF161616),
      onSurface: AppColors.metallicSilver,
      outline: Color(0xFF333333),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),

    /// ✅ CardThemeData (Flutter 3.35+ FIX)
    cardTheme: CardThemeData(
      color: const Color(0xFF161616),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: Color(0xFF2A2A2A),
          width: 1,
        ),
      ),
    ),

    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF161616),
      selectedItemColor: AppColors.softGreen,
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
      showSelectedLabels: false,
      showUnselectedLabels: false,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF222222),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.brandGreen,
      foregroundColor: Colors.white,
      shape: CircleBorder(),
    ),

    textTheme: ThemeData.dark().textTheme,
    iconTheme: const IconThemeData(color: AppColors.metallicSilver),
  );
}
