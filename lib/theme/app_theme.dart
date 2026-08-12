import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color bgDark = Color(0xFF0A0A0A);
  static const Color bgSurface = Color(0xFF141414);
  static const Color bgCard = Color(0xFF1E1E1E);
  static const Color greenPrime = Color(0xFF4CAF50);
  static const Color greenMuted = Color(0xFF2E7D32);
  static const Color greenAccent = Color(0xFF81C784);
  static const Color textPrimary = Color(0xFFEEEEEE);
  static const Color textMuted = Color(0xFF9E9E9E);
  static const Color redDecline = Color(0xFFE53935);
  static const Color borderColor = Color(0xFF2A2A2A);

  static ThemeData get darkTheme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bgDark,
        primaryColor: greenPrime,
        colorScheme: const ColorScheme.dark(
          primary: greenPrime,
          secondary: greenAccent,
          surface: bgSurface,
          error: redDecline,
        ),
        textTheme: GoogleFonts.interTextTheme().copyWith(
          displayLarge: GoogleFonts.inter(
              fontSize: 28, fontWeight: FontWeight.w700, color: textPrimary),
          titleLarge: GoogleFonts.inter(
              fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary),
          titleMedium: GoogleFonts.inter(
              fontSize: 16, fontWeight: FontWeight.w500, color: textPrimary),
          bodyMedium: GoogleFonts.inter(fontSize: 14, color: textMuted),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: bgCard,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: borderColor)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: borderColor)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: greenPrime, width: 2)),
          hintStyle: const TextStyle(color: textMuted, fontSize: 14),
          prefixIconColor: textMuted,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: greenPrime,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle:
                GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: greenPrime,
            side: const BorderSide(color: greenPrime),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: bgSurface,
          selectedItemColor: greenPrime,
          unselectedItemColor: textMuted,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: bgDark,
          elevation: 0,
          iconTheme: IconThemeData(color: textPrimary),
        ),
      );
}
