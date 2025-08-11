import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as notifications;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
// import 'package:permission_handler/permission_handler.dart'; // Commented out to avoid plugin issues
import 'package:csv/csv.dart';

import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/scheduler.dart';
import 'package:lottie/lottie.dart';
import 'dart:math' as math;
import 'package:lottie/lottie.dart';

// Define action IDs for notifications
const String markAsDoneActionId = 'mark_as_done';

// Loading Widget with Lottie Animation
class LoadingWidget extends StatelessWidget {
  final String? message;
  final double size;
  
  const LoadingWidget({
    super.key,
    this.message,
    this.size = 120,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.network(
            'https://lottie.host/embed/8de76ebf-81fe-4064-8627-a96ae50a9a2b/b9WtSX7qqP.lottie',
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              // Fallback to circular progress indicator if Lottie fails to load
              return SizedBox(
                width: size * 0.5,
                height: size * 0.5,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).primaryColor,
                  ),
                ),
              );
            },
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// Loading Overlay Widget
class LoadingOverlay extends StatelessWidget {
  final Widget child;
  final bool isLoading;
  final String? loadingMessage;
  
  const LoadingOverlay({
    super.key,
    required this.child,
    required this.isLoading,
    this.loadingMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: Colors.black.withOpacity(0.3),
            child: LoadingWidget(
              message: loadingMessage ?? 'Loading...',
              size: 100,
            ),
          ),
      ],
    );
  }
}

// Number formatting utility
class NumberFormatter {
  static String formatCurrency(double amount, String currency) {
    final formatter = NumberFormat('#,##0.00');
    return '$currency${formatter.format(amount)}';
  }
  
  static String formatNumber(double number) {
    final formatter = NumberFormat('#,##0.00');
    return formatter.format(number);
  }
  
  // Get currency name for display purposes
  static String getCurrencyName(String currencySymbol) {
    switch (currencySymbol) {
      case '₹':
        return 'Indian Rupee (INR)';
      case '\$':
        return 'US Dollar (USD)';
      case '€':
        return 'Euro (EUR)';
      case '£':
        return 'British Pound (GBP)';
      case '¥':
        return 'Japanese Yen (JPY)';
      case 'R':
        return 'South African Rand (ZAR)';
      case 'C\$':
        return 'Canadian Dollar (CAD)';
      case 'A\$':
        return 'Australian Dollar (AUD)';
      default:
        return 'Unknown Currency';
    }
  }
}

// Global stream controller for reminder updates
class ReminderUpdateNotifier {
  static StreamController<String>? _controller;
  
  static StreamController<String> get controller {
    _controller ??= StreamController<String>.broadcast();
    return _controller!;
  }
  
  static Stream<String> get stream => controller.stream;
  
  static void notifyReminderUpdated(String reminderId) {
    print('=== STREAM NOTIFIER ===');
    print('Notifying reminder updated: $reminderId');
    print('Controller is closed: ${controller.isClosed}');
    print('Stream has listeners: ${controller.hasListener}');
    
    if (!controller.isClosed) {
      controller.add(reminderId);
      print('Added reminder ID to stream');
    } else {
      print('ERROR: Controller is closed, cannot send notification');
      // Recreate controller if it was closed
      _controller = StreamController<String>.broadcast();
      _controller!.add(reminderId);
      print('Recreated controller and added reminder ID');
    }
  }
  
  static void dispose() {
    print('Disposing ReminderUpdateNotifier');
    _controller?.close();
    _controller = null;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notification service which will also set up timezone
  await NotificationService.init();

  // Initialize theme manager
  await ThemeManager.init();

  // Set up background notification handling
  await NotificationService.setupNotificationChannels();

  runApp(const ExpenseTrackerApp());
}

// Theme Variants
enum ThemeVariant {
  standard,      // Default Material 3
  vibrant,       // High contrast, vibrant colors
  minimal,       // Clean, minimal design
  neon,          // Dark with neon accents
  nature,        // Earth tones and natural colors
  ocean,         // Blue and teal ocean theme
  sunset,        // Warm orange and pink tones
  forest,        // Green forest theme
  midnight,      // Deep dark blue theme
  rose,          // Pink and rose theme
  cosmic,        // Purple space theme
  autumn,        // Orange and brown autumn theme
  arctic,        // Cool blue and white theme
  vintage,       // Retro brown and cream theme
}

// Theme Manager
class ThemeManager {
  static const String _themeKey = 'theme_mode';
  static const String _accentColorKey = 'accent_color';
  static const String _themeVariantKey = 'theme_variant';
  static ThemeMode _themeMode = ThemeMode.system;
  static AccentColor _accentColor = AccentColor.teal;
  static ThemeVariant _themeVariant = ThemeVariant.standard;

  static ThemeMode get themeMode => _themeMode;
  static AccentColor get accentColor => _accentColor;
  static ThemeVariant get themeVariant => _themeVariant;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeIndex = prefs.getInt(_themeKey);
    final accentColorIndex = prefs.getInt(_accentColorKey);
    final themeVariantIndex = prefs.getInt(_themeVariantKey);
    
    if (themeModeIndex != null) {
      _themeMode = ThemeMode.values[themeModeIndex];
    }
    
    if (accentColorIndex != null) {
      _accentColor = AccentColor.values[accentColorIndex];
    }
    
    if (themeVariantIndex != null) {
      _themeVariant = ThemeVariant.values[themeVariantIndex];
    }
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
    _themeMode = mode;
  }

  static Future<void> setAccentColor(AccentColor color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_accentColorKey, color.index);
    _accentColor = color;
  }

  static Future<void> setThemeVariant(ThemeVariant variant) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeVariantKey, variant.index);
    _themeVariant = variant;
  }

  static ThemeData getLightTheme() {
    switch (_themeVariant) {
      case ThemeVariant.standard:
        return _getStandardLightTheme();
      case ThemeVariant.vibrant:
        return _getVibrantLightTheme();
      case ThemeVariant.minimal:
        return _getMinimalLightTheme();
      case ThemeVariant.neon:
        return _getNeonLightTheme();
      case ThemeVariant.nature:
        return _getNatureLightTheme();
      case ThemeVariant.ocean:
        return _getOceanLightTheme();
      case ThemeVariant.sunset:
        return _getSunsetLightTheme();
      case ThemeVariant.forest:
        return _getForestLightTheme();
      case ThemeVariant.midnight:
        return _getMidnightLightTheme();
      case ThemeVariant.rose:
        return _getRoseLightTheme();
      case ThemeVariant.cosmic:
        return _getCosmicLightTheme();
      case ThemeVariant.autumn:
        return _getAutumnLightTheme();
      case ThemeVariant.arctic:
        return _getArcticLightTheme();
      case ThemeVariant.vintage:
        return _getVintageLightTheme();
    }
  }

  static ThemeData _getStandardLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _getAccentColor(),
        brightness: Brightness.light,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData.light().textTheme),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
      ),
      cardTheme: const CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _getAccentColor(), width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: MaterialStateProperty.all(
          GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        iconTheme: MaterialStateProperty.all(
          const IconThemeData(size: 24),
        ),
        elevation: 0,
      ),
    );
  }

  static ThemeData getDarkTheme() {
    switch (_themeVariant) {
      case ThemeVariant.standard:
        return _getStandardDarkTheme();
      case ThemeVariant.vibrant:
        return _getVibrantDarkTheme();
      case ThemeVariant.minimal:
        return _getMinimalDarkTheme();
      case ThemeVariant.neon:
        return _getNeonTheme();
      case ThemeVariant.nature:
        return _getNatureDarkTheme();
      case ThemeVariant.ocean:
        return _getOceanDarkTheme();
      case ThemeVariant.sunset:
        return _getSunsetDarkTheme();
      case ThemeVariant.forest:
        return _getForestDarkTheme();
      case ThemeVariant.midnight:
        return _getMidnightTheme();
      case ThemeVariant.rose:
        return _getRoseDarkTheme();
      case ThemeVariant.cosmic:
        return _getCosmicTheme();
      case ThemeVariant.autumn:
        return _getAutumnDarkTheme();
      case ThemeVariant.arctic:
        return _getArcticDarkTheme();
      case ThemeVariant.vintage:
        return _getVintageDarkTheme();
    }
  }

  static ThemeData _getStandardDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _getAccentColor(),
        brightness: Brightness.dark,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.grey.shade900,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      scaffoldBackgroundColor: const Color(0xFF121212),
      cardTheme: const CardThemeData(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        clipBehavior: Clip.antiAlias,
        color: Color(0xFF1E1E1E),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey.shade800,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _getAccentColor(), width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: MaterialStateProperty.all(
          GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        iconTheme: MaterialStateProperty.all(
          const IconThemeData(size: 24),
        ),
        elevation: 0,
        backgroundColor: const Color(0xFF1E1E1E),
      ),
    );
  }

  static ThemeData getLimeDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.lime,
        brightness: Brightness.dark,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: const Color(0xFF1A1C18),
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.lime.shade300,
        ),
      ),
      scaffoldBackgroundColor: const Color(0xFF1A1C18),
      cardTheme: const CardThemeData(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        clipBehavior: Clip.antiAlias,
        color: Color(0xFF232620),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: Colors.lime.shade700,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: Colors.lime.shade600,
        foregroundColor: Colors.black,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF2D2F2B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.lime.shade400, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: MaterialStateProperty.all(
          GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        iconTheme: MaterialStateProperty.all(
          IconThemeData(size: 24, color: Colors.lime.shade300),
        ),
        elevation: 0,
        backgroundColor: const Color(0xFF232620),
      ),
    );
  }

  // Additional Light Theme Variants
  static ThemeData _getVibrantLightTheme() {
    return _getStandardLightTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _getAccentColor(),
        brightness: Brightness.light,
        primary: _getAccentColor().withOpacity(0.9),
        secondary: _getAccentColor().withOpacity(0.7),
      ),
    );
  }

  static ThemeData _getMinimalLightTheme() {
    return _getStandardLightTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.grey.shade600,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: Colors.grey.shade50,
    );
  }

  static ThemeData _getNeonLightTheme() {
    return _getStandardLightTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.cyan,
        brightness: Brightness.light,
      ),
    );
  }

  static ThemeData _getNatureLightTheme() {
    return _getStandardLightTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.green.shade700,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: Colors.green.shade50,
    );
  }

  static ThemeData _getOceanLightTheme() {
    return _getStandardLightTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue.shade600,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: Colors.blue.shade50,
    );
  }

  static ThemeData _getSunsetLightTheme() {
    return _getStandardLightTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.orange.shade600,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: Colors.orange.shade50,
    );
  }

  static ThemeData _getForestLightTheme() {
    return _getStandardLightTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.green.shade800,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: Colors.green.shade50,
    );
  }

  static ThemeData _getMidnightLightTheme() {
    return _getStandardLightTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.indigo.shade800,
        brightness: Brightness.light,
      ),
    );
  }

  static ThemeData _getRoseLightTheme() {
    return _getStandardLightTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.pink.shade400,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: Colors.pink.shade50,
    );
  }

  static ThemeData _getCosmicLightTheme() {
    return _getStandardLightTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple.shade600,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: Colors.deepPurple.shade50,
    );
  }

  static ThemeData _getAutumnLightTheme() {
    return _getStandardLightTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.brown.shade600,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: Colors.brown.shade50,
    );
  }

  static ThemeData _getArcticLightTheme() {
    return _getStandardLightTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.lightBlue.shade600,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: Colors.lightBlue.shade50,
    );
  }

  static ThemeData _getVintageLightTheme() {
    return _getStandardLightTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.brown.shade400,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFFAF7F0),
    );
  }

  // Additional Dark Theme Variants
  static ThemeData _getVibrantDarkTheme() {
    return _getStandardDarkTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _getAccentColor(),
        brightness: Brightness.dark,
        primary: _getAccentColor(),
        secondary: _getAccentColor().withOpacity(0.8),
      ),
    );
  }

  static ThemeData _getMinimalDarkTheme() {
    return _getStandardDarkTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.grey.shade700,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0A0A0A),
    );
  }

  static ThemeData _getNeonTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.cyan,
        brightness: Brightness.dark,
        primary: Colors.cyan,
        secondary: Colors.pink,
      ),
      scaffoldBackgroundColor: const Color(0xFF000012),
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
    );
  }

  static ThemeData _getNatureDarkTheme() {
    return _getStandardDarkTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.green.shade700,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0D1F0D),
    );
  }

  static ThemeData _getOceanDarkTheme() {
    return _getStandardDarkTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue.shade700,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0A1929),
    );
  }

  static ThemeData _getSunsetDarkTheme() {
    return _getStandardDarkTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepOrange,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF1A0E0A),
    );
  }

  static ThemeData _getForestDarkTheme() {
    return _getStandardDarkTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.green.shade800,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0F1B0F),
    );
  }

  static ThemeData _getMidnightTheme() {
    return _getStandardDarkTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.indigo.shade900,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0A0E1A),
    );
  }

  static ThemeData _getRoseDarkTheme() {
    return _getStandardDarkTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.pink.shade600,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF1A0A14),
    );
  }

  static ThemeData _getCosmicTheme() {
    return _getStandardDarkTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0F0A1A),
    );
  }

  static ThemeData _getAutumnDarkTheme() {
    return _getStandardDarkTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.brown.shade700,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF1A1410),
    );
  }

  static ThemeData _getArcticDarkTheme() {
    return _getStandardDarkTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.lightBlue.shade700,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0A1419),
    );
  }

  static ThemeData _getVintageDarkTheme() {
    return _getStandardDarkTheme().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.brown.shade600,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF1A1612),
    );
  }

  static Color _getAccentColor() {
    switch (_accentColor) {
      case AccentColor.teal:
        return Colors.teal;
      case AccentColor.purple:
        return Colors.purple;
      case AccentColor.orange:
        return Colors.orange;
      case AccentColor.blue:
        return Colors.blue;
      case AccentColor.red:
        return Colors.red;
      case AccentColor.green:
        return Colors.green;
      case AccentColor.pink:
        return Colors.pink;
      case AccentColor.indigo:
        return Colors.indigo;
      case AccentColor.cyan:
        return Colors.cyan;
      case AccentColor.amber:
        return Colors.amber;
      case AccentColor.deepOrange:
        return Colors.deepOrange;
      case AccentColor.lightBlue:
        return Colors.lightBlue;
      case AccentColor.lime:
        return Colors.lime;
      case AccentColor.deepPurple:
        return Colors.deepPurple;
      case AccentColor.brown:
        return Colors.brown;
      case AccentColor.blueGrey:
        return Colors.blueGrey;
      case AccentColor.yellow:
        return Colors.yellow;
      case AccentColor.lightGreen:
        return Colors.lightGreen;
      case AccentColor.pinkAccent:
        return Colors.pinkAccent;
      case AccentColor.indigoAccent:
        return Colors.indigoAccent;
    }
  }
}

enum AccentColor { 
  teal, purple, orange, blue, red, green, pink, indigo, 
  cyan, amber, deepOrange, lightBlue, lime, deepPurple, 
  brown, blueGrey, yellow, lightGreen, pinkAccent, indigoAccent 
}

class ExpenseTrackerApp extends StatefulWidget {
  const ExpenseTrackerApp({Key? key}) : super(key: key);

  @override
  State<ExpenseTrackerApp> createState() => _ExpenseTrackerAppState();
}

class _ExpenseTrackerAppState extends State<ExpenseTrackerApp> {
  ThemeMode _currentThemeMode = ThemeManager.themeMode;
  AccentColor _currentAccentColor = ThemeManager.accentColor;
  ThemeVariant _currentThemeVariant = ThemeManager.themeVariant;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ExTrack',
      debugShowCheckedModeBanner: false,
      theme: ThemeManager.getLightTheme(),
      darkTheme: ThemeManager.getDarkTheme(),
      themeMode: ThemeManager.themeMode,
      home: const SplashScreen(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check if theme settings have changed
    if (_currentThemeMode != ThemeManager.themeMode ||
        _currentAccentColor != ThemeManager.accentColor ||
        _currentThemeVariant != ThemeManager.themeVariant) {
      setState(() {
        _currentThemeMode = ThemeManager.themeMode;
        _currentAccentColor = ThemeManager.accentColor;
        _currentThemeVariant = ThemeManager.themeVariant;
      });
    }
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );
    
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
      ),
    );
    
    _controller.forward();
    _navigateToMainScreen();
  }

  Future<void> _navigateToMainScreen() async {
    // Wait for animation to complete and show splash for 3 seconds
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const MainScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = 0.0;
          const end = 1.0;
          const curve = Curves.easeInOut;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var fadeAnimation = animation.drive(tween);
          return FadeTransition(opacity: fadeAnimation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDarkMode 
                ? ThemeManager.themeMode == ThemeMode.system
                    ? [const Color(0xFF121212), const Color(0xFF1E1E1E)]
                    : ThemeManager.themeMode == ThemeMode.dark
                        ? [const Color(0xFF121212), const Color(0xFF1E1E1E)]
                        : [const Color(0xFF1A1C18), const Color(0xFF2D3A24)] // Lime dark theme
                : [Colors.white, const Color(0xFFF8F9FA)],
          ),
        ),
        child: Stack(
          children: [
            // Floating background elements
            ...List.generate(6, (index) {
              return Positioned(
                left: (index * 60.0) + 20,
                top: (index * 80.0) + 100,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(
                        10 * math.sin(_controller.value * 2 * math.pi + index),
                        10 * math.cos(_controller.value * 2 * math.pi + index),
                      ),
                      child: Opacity(
                        opacity: 0.1,
                        child: Icon(
                          [Icons.attach_money, Icons.trending_up, Icons.account_balance_wallet, 
                           Icons.savings, Icons.pie_chart, Icons.analytics][index % 6],
                          size: 24,
                          color: ThemeManager._getAccentColor(),
                        ),
                      ),
                    );
                  },
                ),
              );
            }),
            // Main content
            Center(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                    // Logo image
                    Image.asset('assets/logo/track.png', width: 180),
                    const SizedBox(height: 24),
                    Text(
                      'ExTrack',
                      style: GoogleFonts.poppins(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your Personal Finance Tracker',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: isDarkMode ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: 1.0 + (0.05 * math.sin(_controller.value * 4 * math.pi)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: ThemeManager._getAccentColor().withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: ThemeManager._getAccentColor().withOpacity(0.3),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: ThemeManager._getAccentColor().withOpacity(0.2),
                                  blurRadius: 8,
                                  spreadRadius: 0,
                                ),
                              ],
                            ),
                            child: Text(
                              'v2.0.0 - Advanced Budgeting',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: ThemeManager._getAccentColor(),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: Lottie.network(
                        'https://lottie.host/embed/ff6b1182-6bf1-4697-ba0e-e27d8cf2929a/PHCPnAuukT.lottie',
                        fit: BoxFit.contain,
                        repeat: true,
                        animate: true,
                        errorBuilder: (context, error, stackTrace) {
                          // Fallback to local asset if network fails
                          return Lottie.asset(
                            'assets/animations/splash_animation.lottie',
                            fit: BoxFit.contain,
                            repeat: true,
                            animate: true,
                            errorBuilder: (context, error, stackTrace) {
                              // Final fallback to circular progress indicator
                              return CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  ThemeManager.themeMode == ThemeMode.light
                                      ? ThemeManager._getAccentColor()
                                      : ThemeManager.themeMode == ThemeMode.dark
                                          ? ThemeManager._getAccentColor()
                                          : Colors.lime.shade400,
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: Text(
                        'Loading your financial dashboard...',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: isDarkMode ? Colors.white60 : Colors.black45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Notification Service
class NotificationService {
  static final notifications.FlutterLocalNotificationsPlugin _notifications =
      notifications.FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    // Initialize timezone information first
    await _initializeTimeZone();

    const androidSettings = notifications.AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = notifications.DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = notifications.InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    // Request notification permissions
    await requestNotificationPermissions();

    // Handle permissions on Android
    if (Platform.isAndroid) {
      final notifications.AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notifications
              .resolvePlatformSpecificImplementation<
                notifications.AndroidFlutterLocalNotificationsPlugin
              >();

      // Request notification permission
      final bool? areNotificationsEnabled = await androidImplementation
          ?.areNotificationsEnabled();

      if (areNotificationsEnabled == false) {
        print(
          "Notifications not enabled, but we won't request permission programmatically as it varies by Android version",
        );
        // Permission will be requested by the system when a notification is shown
      }

      // Request exact alarm permission for scheduled notifications
      await requestExactAlarmPermission();
    }
  }

  // Setup notification channels for Android
  static Future<void> setupNotificationChannels() async {
    if (Platform.isAndroid) {
      // Create maximum importance channel for reminders (critical for closed app notifications)
      const reminderChannel = notifications.AndroidNotificationChannel(
        'expense_reminder',
        'Expense Reminders',
        description: 'Critical notifications for expense reminders - these will show even when app is closed',
        importance: notifications.Importance.max, // Maximum importance for closed app reliability
        enableVibration: true,
        playSound: true,
        showBadge: true,
        // Additional settings for better reliability
        enableLights: true,
        ledColor: Color.fromARGB(255, 255, 0, 0),
      );

      // Create test channel
      const testChannel = notifications.AndroidNotificationChannel(
        'test_channel',
        'Test Notifications',
        description: 'For testing notifications',
        importance: notifications.Importance.max,
        enableVibration: true,
        playSound: true,
        showBadge: true,
      );

      final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
          notifications.AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(reminderChannel);
        await androidPlugin.createNotificationChannel(testChannel);
        
        print('Notification channels created successfully');
        
        // Verify channels were created
        final channels = await androidPlugin.getNotificationChannels();
        print('Available channels: ${channels?.map((c) => c.id).toList()}');
      }
    }
  }

  // Handle notification response when app is running
  static void onNotificationResponse(notifications.NotificationResponse response) {
    print("=== NOTIFICATION RESPONSE RECEIVED ===");
    print("Payload: ${response.payload}");
    print("Action ID: ${response.actionId}");
    print("Mark as done action ID: $markAsDoneActionId");
    print("Is mark as done action: ${response.actionId == markAsDoneActionId}");
    
    // Also save to SharedPreferences for debugging
    _saveDebugLog("Notification response received: ${response.actionId}");
    
    // Handle the mark as done action
    if (response.actionId == markAsDoneActionId) {
      print("Calling _handleMarkAsDoneAction...");
      _saveDebugLog("Mark as done action triggered");
      _handleMarkAsDoneAction(response.payload);
    } else {
      // Regular notification tap
      print("Regular notification tapped: ${response.payload}");
      _saveDebugLog("Regular notification tapped");
    }
  }
  
  // Save debug log to SharedPreferences
  static Future<void> _saveDebugLog(String message) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = DateTime.now().toIso8601String();
      final logMessage = "$timestamp: $message";
      
      // Get existing logs
      final List<String> logs = prefs.getStringList('debug_logs') ?? [];
      logs.add(logMessage);
      
      // Keep only last 50 logs
      if (logs.length > 50) {
        logs.removeRange(0, logs.length - 50);
      }
      
      await prefs.setStringList('debug_logs', logs);
    } catch (e) {
      print('Error saving debug log: $e');
    }
  }
  
  // Handle the mark as done action
  static Future<void> _handleMarkAsDoneAction(String? payload) async {
    print('=== MARK AS DONE ACTION STARTED ===');
    print('Payload: $payload');
    
    if (payload == null) {
      print('Payload is null, returning');
      return;
    }
    
    try {
      // Parse the payload
      final Map<String, dynamic> payloadData = json.decode(payload);
      final String? reminderId = payloadData['id'];
      print('Parsed reminder ID: $reminderId');
      
      if (reminderId != null) {
        // Load reminders
        final prefs = await SharedPreferences.getInstance();
        final String? remindersJson = prefs.getString('reminders');
        print('Loaded reminders JSON: ${remindersJson?.substring(0, 100)}...');
        
        if (remindersJson != null) {
          final List<dynamic> decoded = json.decode(remindersJson);
          List<Reminder> reminders = decoded.map((item) => Reminder.fromJson(item)).toList();
          print('Total reminders loaded: ${reminders.length}');
          
          // Find and update the reminder
          final index = reminders.indexWhere((r) => r.id == reminderId);
          print('Found reminder at index: $index');
          
          if (index != -1) {
            print('Before update - isActive: ${reminders[index].isActive}');
            
            // Mark as done (set isActive to false)
            final updatedReminder = Reminder(
              id: reminders[index].id,
              title: reminders[index].title,
              description: reminders[index].description,
              dateTime: reminders[index].dateTime,
              type: reminders[index].type,
              isActive: false,
              amount: reminders[index].amount,
            );
            
            reminders[index] = updatedReminder;
            print('After update - isActive: ${reminders[index].isActive}');
            
            // Save updated reminders
            final String encoded = json.encode(
              reminders.map((r) => r.toJson()).toList(),
            );
            await prefs.setString('reminders', encoded);
            print('Saved updated reminders to SharedPreferences');
            
            print('Reminder marked as done: $reminderId');
            
            // Notify the UI immediately using the stream
            print('Sending stream notification...');
            ReminderUpdateNotifier.notifyReminderUpdated(reminderId);
            print('Stream notification sent');
            
            // Also keep the SharedPreferences approach as backup
            await prefs.setBool('reminder_updated', true);
            await prefs.setString('last_updated_reminder', reminderId);
            print('Set backup SharedPreferences flags');
            
            // Cancel the notification after a small delay to ensure callback is processed
            await Future.delayed(const Duration(milliseconds: 500));
            await cancelNotification(reminderId.hashCode);
            print('Cancelled notification with ID: ${reminderId.hashCode}');
          } else {
            print('ERROR: Reminder with ID $reminderId not found');
          }
        } else {
          print('ERROR: No reminders found in SharedPreferences');
        }
      } else {
        print('ERROR: No reminder ID found in payload');
      }
    } catch (e) {
      print('ERROR handling mark as done action: $e');
      print('Stack trace: ${StackTrace.current}');
    }
    
    print('=== MARK AS DONE ACTION COMPLETED ===');
  }

  // Request notification permissions
  static Future<void> requestNotificationPermissions() async {
    // For iOS
    if (Platform.isIOS) {
      await _notifications
          .resolvePlatformSpecificImplementation<
              notifications.IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }
    
    // For Android 13+ (API level 33+)
    if (Platform.isAndroid) {
      final androidImplementation = _notifications
          .resolvePlatformSpecificImplementation<
              notifications.AndroidFlutterLocalNotificationsPlugin>();
              
      await androidImplementation?.requestNotificationsPermission();
    }
  }

  // Initialize timezone information
  static Future<void> _initializeTimeZone() async {
    try {
      // Initialize timezone database
      tz.initializeTimeZones();

      // Set to Asia/Kolkata timezone
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

      print("Timezone initialized to Asia/Kolkata successfully");
    } catch (e) {
      print("Error initializing timezone: $e");
      // Fallback to UTC if there's an error
      try {
        tz.setLocalLocation(tz.UTC);
        print("Timezone fallback to UTC");
      } catch (e) {
        print("Error setting UTC timezone: $e");
      }
    }
  }

  // Check if notifications are properly enabled
  static Future<bool> areNotificationsEnabled() async {
    if (Platform.isAndroid) {
      final androidImplementation = _notifications
          .resolvePlatformSpecificImplementation<
              notifications.AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidImplementation != null) {
        final bool? enabled = await androidImplementation.areNotificationsEnabled();
        return enabled ?? false;
      }
    }
    return true; // Assume enabled for iOS
  }

  // Check if exact alarms are enabled (Android 12+)
  static Future<bool> canScheduleExactNotifications() async {
    if (Platform.isAndroid) {
      final androidImplementation = _notifications
          .resolvePlatformSpecificImplementation<
              notifications.AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidImplementation != null) {
        try {
          // This will return true if exact alarms are allowed
          return true; // We'll assume it's allowed and handle errors in scheduling
        } catch (e) {
          print("Error checking exact alarm permission: $e");
          return false;
        }
      }
    }
    return true; // iOS doesn't have this restriction
  }

  // Show notification settings dialog
  static Future<void> showNotificationSettingsDialog(BuildContext context) async {
    final bool notificationsEnabled = await areNotificationsEnabled();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(notificationsEnabled ? 'Notification Tips' : 'Notifications Disabled'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!notificationsEnabled) ...[
                const Text(
                  'Notifications are disabled. Please enable them first.',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
              ],
              const Text(
                'For notifications when app is completely closed:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('📱 Android Settings:'),
              const Text('1. Settings > Apps > ExTrack > Notifications'),
              const Text('2. Enable "Allow notifications"'),
              const Text('3. Set importance to "High" or "Urgent"'),
              const SizedBox(height: 8),
              const Text('⏰ Alarm Permissions:'),
              const Text('4. Settings > Apps > ExTrack > Permissions'),
              const Text('5. Allow "Alarms & reminders"'),
              const SizedBox(height: 8),
              const Text('🔋 Battery Optimization:'),
              const Text('6. Settings > Battery > Battery optimization'),
              const Text('7. Find ExTrack and select "Don\'t optimize"'),
              const SizedBox(height: 8),
              const Text('🚀 Background Activity:'),
              const Text('8. Settings > Apps > ExTrack > Battery'),
              const Text('9. Allow "Background activity"'),
              const SizedBox(height: 16),
              const Text(
                'Note: Steps may vary by device manufacturer (Samsung, Xiaomi, etc.)',
                style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          if (!notificationsEnabled)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
        ],
      ),
    );
  }

  // Open app settings (Android)
  static Future<void> _openAppSettings() async {
    if (Platform.isAndroid) {
      try {
        // This would require a method channel implementation
        // For now, we'll just show instructions
        print("Opening app settings...");
      } catch (e) {
        print("Error opening app settings: $e");
      }
    }
  }

  // Function to request exact alarm permission on Android
  static Future<void> requestExactAlarmPermission() async {
    if (!Platform.isAndroid) return;

    try {
      final notifications.AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notifications
              .resolvePlatformSpecificImplementation<
                notifications.AndroidFlutterLocalNotificationsPlugin
              >();

      if (androidImplementation != null) {
        await androidImplementation.requestExactAlarmsPermission();
        print("Requested exact alarms permission");
      }
    } catch (e) {
      print("Error requesting exact alarms permission: $e");
    }
  }

  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    try {
      print('Scheduling notification for: ${scheduledDate.toString()}, ID: $id');

      // Check if notifications are enabled
      final bool notificationsEnabled = await areNotificationsEnabled();
      if (!notificationsEnabled) {
        print('Notifications are disabled. Cannot schedule notification.');
        throw Exception('Notifications are disabled');
      }

      // Calculate proper time zone aware DateTime
      final tz.TZDateTime scheduledTZDateTime = _nextInstanceOfTime(scheduledDate);
      print('TZ scheduled time: ${scheduledTZDateTime.toString()}');

      // Define the mark as done action with different configurations for better reliability
      final List<notifications.AndroidNotificationAction> actions = [
        const notifications.AndroidNotificationAction(
          markAsDoneActionId,
          'Mark as Done',
          showsUserInterface: false,
          cancelNotification: false, // Don't auto-cancel to ensure callback is triggered
          allowGeneratedReplies: false,
        ),
      ];

      // Enhanced Android notification details for better reliability when app is closed
      final androidDetails = notifications.AndroidNotificationDetails(
        'expense_reminder',
        'Expense Reminders',
        channelDescription: 'Critical notifications for expense reminders',
        importance: notifications.Importance.max, // Changed to max for better reliability
        priority: notifications.Priority.max, // Changed to max
        category: notifications.AndroidNotificationCategory.alarm, // Changed to alarm for better system handling
        fullScreenIntent: true,
        visibility: notifications.NotificationVisibility.public,
        icon: '@mipmap/ic_launcher',
        playSound: true,
        enableLights: true,
        enableVibration: true,
        ongoing: false,
        autoCancel: true,
        actions: actions,
        // Additional flags for better reliability
        additionalFlags: Int32List.fromList(<int>[
          4, // FLAG_INSISTENT - keeps notification active
          8, // FLAG_NO_CLEAR - prevents user from dismissing
        ]),
        // Wake up the device
        showWhen: true,
        when: scheduledTZDateTime.millisecondsSinceEpoch,
        // Ensure it shows even in Do Not Disturb mode
        channelShowBadge: true,
        // Make it a high priority notification
        ticker: title,
      );

      final iosDetails = notifications.DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        badgeNumber: 1,
        // iOS specific settings for better reliability
        interruptionLevel: notifications.InterruptionLevel.critical,
      );

      // For immediate notifications (within 10 seconds), use show() instead of zonedSchedule
      if (scheduledDate.difference(DateTime.now()).inSeconds < 10) {
        await _notifications.show(
          id,
          title,
          body,
          notifications.NotificationDetails(
            android: androidDetails,
            iOS: iosDetails,
          ),
          payload: payload,
        );
        print('Immediate notification shown with ID: $id');
        return;
      }

      // Try exact scheduling first (most reliable for closed apps)
      try {
        await _notifications.zonedSchedule(
          id,
          title,
          body,
          scheduledTZDateTime,
          notifications.NotificationDetails(
            android: androidDetails,
            iOS: iosDetails,
          ),
          androidScheduleMode: notifications.AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: notifications.DateTimeComponents.dateAndTime,
          payload: payload,
        );
        print('Notification scheduled with exact alarm, ID: $id');
      } catch (exactError) {
        print('Exact alarm scheduling failed: $exactError');
        
        // Fallback to inexact scheduling
        try {
          // Create a modified android details for inexact scheduling
          final inexactAndroidDetails = notifications.AndroidNotificationDetails(
            'expense_reminder',
            'Expense Reminders',
            channelDescription: 'Critical notifications for expense reminders',
            importance: notifications.Importance.max,
            priority: notifications.Priority.max,
            category: notifications.AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
            visibility: notifications.NotificationVisibility.public,
            icon: '@mipmap/ic_launcher',
            playSound: true,
            enableLights: true,
            enableVibration: true,
            ongoing: false,
            autoCancel: true,
            actions: actions,
            // Reduced flags for inexact scheduling
            additionalFlags: Int32List.fromList(<int>[4]),
            showWhen: true,
            when: scheduledTZDateTime.millisecondsSinceEpoch,
            channelShowBadge: true,
            ticker: title,
          );

          await _notifications.zonedSchedule(
            id,
            title,
            body,
            scheduledTZDateTime,
            notifications.NotificationDetails(
              android: inexactAndroidDetails,
              iOS: iosDetails,
            ),
            androidScheduleMode: notifications.AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: notifications.DateTimeComponents.dateAndTime,
            payload: payload,
          );
          print('Notification scheduled with inexact alarm, ID: $id');
        } catch (inexactError) {
          print('Both exact and inexact scheduling failed: $inexactError');
          throw inexactError;
        }
      }
    } catch (e) {
      print('Failed to schedule notification entirely: $e');
      rethrow;
    }
  }

  // Helper method to ensure proper timezone handling
  static tz.TZDateTime _nextInstanceOfTime(DateTime scheduledDate) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledTZDateTime = tz.TZDateTime.from(
      scheduledDate,
      tz.local,
    );

    // If the scheduled time is in the past, reschedule intelligently
    if (scheduledTZDateTime.isBefore(now)) {
      print('Scheduled time is in the past, adjusting to future');

      // If it's the same day, add one day
      if (scheduledTZDateTime.day == now.day &&
          scheduledTZDateTime.month == now.month &&
          scheduledTZDateTime.year == now.year) {
        scheduledTZDateTime = scheduledTZDateTime.add(const Duration(days: 1));
      } else {
        // Otherwise, keep the time but change to today or tomorrow
        final newDateTime = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day,
          scheduledDate.hour,
          scheduledDate.minute,
        );

        // If the new time is still in the past (earlier today), push to tomorrow
        if (newDateTime.isBefore(now)) {
          scheduledTZDateTime = newDateTime.add(const Duration(days: 1));
        } else {
          scheduledTZDateTime = newDateTime;
        }
      }

      print('Adjusted to: ${scheduledTZDateTime.toString()}');
    }

    return scheduledTZDateTime;
  }

  static Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  static Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  static Future<void> showTestNotification() async {
    try {
      final int id = DateTime.now().millisecondsSinceEpoch % 100000;
      final String testId = 'test_notification_$id';

      // Define the mark as done action
      final List<notifications.AndroidNotificationAction> actions = [
        const notifications.AndroidNotificationAction(
          markAsDoneActionId,
          'Mark as Done',
          showsUserInterface: false,
          cancelNotification: false, // Don't auto-cancel to ensure callback is triggered
          allowGeneratedReplies: false,
        ),
      ];

      await _notifications.show(
        id,
        'Test Notification',
        'This is a test notification to verify that notifications are working properly. Try the "Mark as Done" action!',
        notifications.NotificationDetails(
          android: notifications.AndroidNotificationDetails(
            'test_channel',
            'Test Notifications',
            channelDescription: 'For testing notifications',
            importance: notifications.Importance.max,
            priority: notifications.Priority.high,
            category: notifications.AndroidNotificationCategory.message,
            visibility: notifications.NotificationVisibility.public,
            icon: '@mipmap/ic_launcher',
            playSound: true,
            enableLights: true,
            enableVibration: true,
            actions: actions,
          ),
          iOS: const notifications.DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            badgeNumber: 1,
          ),
        ),
        payload: json.encode({'test': true, 'id': testId}),
      );

      print('Test notification shown with ID: $id, testId: $testId');
    } catch (e) {
      print('Error showing test notification: $e');
    }
  }

  static Future<void> showBudgetNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await _notifications.show(
        id,
        title,
        body,
        const notifications.NotificationDetails(
          android: notifications.AndroidNotificationDetails(
            'budget_alerts',
            'Budget Alerts',
            channelDescription: 'Notifications for budget alerts and warnings',
            importance: notifications.Importance.high,
            priority: notifications.Priority.high,
            category: notifications.AndroidNotificationCategory.reminder,
            visibility: notifications.NotificationVisibility.public,
            icon: '@mipmap/ic_launcher',
            playSound: true,
            enableLights: true,
            enableVibration: true,
            color: Color(0xFFFF6B6B), // Red color for budget alerts
          ),
          iOS: const notifications.DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            badgeNumber: 1,
            interruptionLevel: notifications.InterruptionLevel.timeSensitive,
          ),
        ),
      );

      print('Budget notification shown: $title');
    } catch (e) {
      print('Error showing budget notification: $e');
    }
  }
}

// This function handles notification taps when the app is terminated
@pragma('vm:entry-point')
void notificationTapBackground(notifications.NotificationResponse response) {
  // This function will be called when the app is terminated and user taps on notification
  print("Notification tapped in background: ${response.payload}, action: ${response.actionId}");
  
  // If it's a mark as done action, handle it
  if (response.actionId == markAsDoneActionId) {
    NotificationService._handleMarkAsDoneAction(response.payload);
  }
}

// Models
class Transaction {
  final String id;
  final double amount;
  final String category;
  final DateTime date;
  final String? notes;
  final TransactionType type;

  Transaction({
    required this.id,
    required this.amount,
    required this.category,
    required this.date,
    this.notes,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'amount': amount,
    'category': category,
    'date': date.toIso8601String(),
    'notes': notes,
    'type': type.toString(),
  };

  factory Transaction.fromJson(Map<String, dynamic> json) => Transaction(
    id: json['id'],
    amount: json['amount'].toDouble(),
    category: json['category'],
    date: DateTime.parse(json['date']),
    notes: json['notes'],
    type: json['type'] == 'TransactionType.income'
        ? TransactionType.income
        : TransactionType.expense,
  );
}

enum TransactionType { income, expense }

class Category {
  final String name;
  final IconData icon;
  final Color color;

  Category({required this.name, required this.icon, required this.color});
}

// Reminder Model
class Reminder {
  final String id;
  final String title;
  final String description;
  final DateTime dateTime;
  final ReminderType type;
  final bool isActive;
  final double? amount;

  Reminder({
    required this.id,
    required this.title,
    required this.description,
    required this.dateTime,
    required this.type,
    this.isActive = true,
    this.amount,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'dateTime': dateTime.toIso8601String(),
    'type': type.toString(),
    'isActive': isActive,
    'amount': amount,
  };

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
    id: json['id'],
    title: json['title'],
    description: json['description'],
    dateTime: DateTime.parse(json['dateTime']),
    type: ReminderType.values.firstWhere((e) => e.toString() == json['type']),
    isActive: json['isActive'] ?? true,
    amount: json['amount']?.toDouble(),
  );
}

enum ReminderType {
  billPayment,
  salaryReminder,
  budgetReview,
  subscription,
  savingsGoal,
  taxPayment,
  custom,
}

// Budget Models
class Budget {
  final String id;
  final String categoryName;
  final double amount;
  final BudgetPeriod period;
  final DateTime startDate;
  final DateTime endDate;
  final bool isActive;
  final List<double> alertThresholds; // [50, 75, 90, 100]
  final DateTime createdAt;
  final DateTime updatedAt;

  Budget({
    required this.id,
    required this.categoryName,
    required this.amount,
    required this.period,
    required this.startDate,
    required this.endDate,
    this.isActive = true,
    this.alertThresholds = const [50.0, 75.0, 90.0, 100.0],
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'categoryName': categoryName,
    'amount': amount,
    'period': period.toString(),
    'startDate': startDate.toIso8601String(),
    'endDate': endDate.toIso8601String(),
    'isActive': isActive,
    'alertThresholds': alertThresholds,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Budget.fromJson(Map<String, dynamic> json) => Budget(
    id: json['id'],
    categoryName: json['categoryName'],
    amount: json['amount'].toDouble(),
    period: BudgetPeriod.values.firstWhere((e) => e.toString() == json['period']),
    startDate: DateTime.parse(json['startDate']),
    endDate: DateTime.parse(json['endDate']),
    isActive: json['isActive'] ?? true,
    alertThresholds: List<double>.from(json['alertThresholds'] ?? [50.0, 75.0, 90.0, 100.0]),
    createdAt: DateTime.parse(json['createdAt']),
    updatedAt: DateTime.parse(json['updatedAt']),
  );

  Budget copyWith({
    String? id,
    String? categoryName,
    double? amount,
    BudgetPeriod? period,
    DateTime? startDate,
    DateTime? endDate,
    bool? isActive,
    List<double>? alertThresholds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Budget(
      id: id ?? this.id,
      categoryName: categoryName ?? this.categoryName,
      amount: amount ?? this.amount,
      period: period ?? this.period,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isActive: isActive ?? this.isActive,
      alertThresholds: alertThresholds ?? this.alertThresholds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

enum BudgetPeriod {
  weekly,
  monthly,
  quarterly,
  yearly,
  custom
}

class BudgetProgress {
  final String budgetId;
  final double spent;
  final double remaining;
  final double percentage;
  final List<Transaction> transactions;
  final DateTime lastUpdated;
  final BudgetStatus status;

  BudgetProgress({
    required this.budgetId,
    required this.spent,
    required this.remaining,
    required this.percentage,
    required this.transactions,
    required this.lastUpdated,
    required this.status,
  });

  factory BudgetProgress.calculate(Budget budget, List<Transaction> allTransactions) {
    // Filter transactions for this budget's category and time period
    final categoryTransactions = allTransactions.where((transaction) =>
      transaction.category == budget.categoryName &&
      transaction.type == TransactionType.expense &&
      transaction.date.isAfter(budget.startDate.subtract(const Duration(days: 1))) &&
      transaction.date.isBefore(budget.endDate.add(const Duration(days: 1)))
    ).toList();

    final spent = categoryTransactions.fold<double>(0, (sum, transaction) => sum + transaction.amount);
    final remaining = budget.amount - spent;
    final percentage = budget.amount > 0 ? (spent / budget.amount) * 100.0 : 0.0;

    BudgetStatus status;
    if (percentage >= 100) {
      status = BudgetStatus.exceeded;
    } else if (percentage >= 90) {
      status = BudgetStatus.warning;
    } else if (percentage >= 75) {
      status = BudgetStatus.approaching;
    } else {
      status = BudgetStatus.safe;
    }

    return BudgetProgress(
      budgetId: budget.id,
      spent: spent,
      remaining: remaining,
      percentage: percentage,
      transactions: categoryTransactions,
      lastUpdated: DateTime.now(),
      status: status,
    );
  }
}

enum BudgetStatus {
  safe,      // < 75%
  approaching, // 75-89%
  warning,   // 90-99%
  exceeded   // >= 100%
}

class BudgetAlert {
  final String id;
  final String budgetId;
  final AlertType type;
  final double threshold;
  final DateTime triggeredAt;
  final bool isRead;
  final String message;

  BudgetAlert({
    required this.id,
    required this.budgetId,
    required this.type,
    required this.threshold,
    required this.triggeredAt,
    this.isRead = false,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'budgetId': budgetId,
    'type': type.toString(),
    'threshold': threshold,
    'triggeredAt': triggeredAt.toIso8601String(),
    'isRead': isRead,
    'message': message,
  };

  factory BudgetAlert.fromJson(Map<String, dynamic> json) => BudgetAlert(
    id: json['id'],
    budgetId: json['budgetId'],
    type: AlertType.values.firstWhere((e) => e.toString() == json['type']),
    threshold: json['threshold'].toDouble(),
    triggeredAt: DateTime.parse(json['triggeredAt']),
    isRead: json['isRead'] ?? false,
    message: json['message'],
  );
}

enum AlertType {
  approaching, // 75%
  warning,     // 90%
  exceeded,    // 100%+
  weeklyReport
}

enum FilterPeriod {
  all,
  today,
  yesterday,
  thisWeek,
  lastWeek,
  thisMonth,
  lastMonth,
  thisYear,
  lastYear,
  custom,
}

// Data Manager
class DataManager {
  static const String _transactionsKey = 'transactions';
  static const String _remindersKey = 'reminders';
  static const String _currencyKey = 'currency';

  static Future<List<Transaction>> getTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final String? transactionsJson = prefs.getString(_transactionsKey);
    if (transactionsJson == null) return [];

    final List<dynamic> decoded = json.decode(transactionsJson);
    return decoded.map((item) => Transaction.fromJson(item)).toList();
  }

  static Future<void> saveTransactions(List<Transaction> transactions) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = json.encode(
      transactions.map((t) => t.toJson()).toList(),
    );
    await prefs.setString(_transactionsKey, encoded);
  }

  static Future<List<Reminder>> getReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final String? remindersJson = prefs.getString(_remindersKey);
    if (remindersJson == null) return [];

    final List<dynamic> decoded = json.decode(remindersJson);
    return decoded.map((item) => Reminder.fromJson(item)).toList();
  }

  static Future<void> saveReminders(List<Reminder> reminders) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = json.encode(
      reminders.map((r) => r.toJson()).toList(),
    );
    await prefs.setString(_remindersKey, encoded);
  }

  static Future<String> getCurrency() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_currencyKey) ?? '\$';
  }

  static Future<void> setCurrency(String currency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currencyKey, currency);
  }

  // Budget data management
  static const String _budgetsKey = 'budgets';
  static const String _budgetAlertsKey = 'budget_alerts';

  static Future<List<Budget>> getBudgets() async {
    final prefs = await SharedPreferences.getInstance();
    final String? budgetsJson = prefs.getString(_budgetsKey);
    if (budgetsJson == null) return [];

    final List<dynamic> decoded = json.decode(budgetsJson);
    return decoded.map((item) => Budget.fromJson(item)).toList();
  }

  static Future<void> saveBudgets(List<Budget> budgets) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = json.encode(
      budgets.map((b) => b.toJson()).toList(),
    );
    await prefs.setString(_budgetsKey, encoded);
  }

  static Future<List<BudgetAlert>> getBudgetAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    final String? alertsJson = prefs.getString(_budgetAlertsKey);
    if (alertsJson == null) return [];

    final List<dynamic> decoded = json.decode(alertsJson);
    return decoded.map((item) => BudgetAlert.fromJson(item)).toList();
  }

  static Future<void> saveBudgetAlerts(List<BudgetAlert> alerts) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = json.encode(
      alerts.map((a) => a.toJson()).toList(),
    );
    await prefs.setString(_budgetAlertsKey, encoded);
  }
}

// App Lifecycle Observer
class _AppLifecycleObserver extends WidgetsBindingObserver {
  final Function onResume;

  _AppLifecycleObserver({required this.onResume});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResume();
    }
  }
}

// Main Screen with Navigation
class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  List<Transaction> _transactions = [];
  List<Reminder> _reminders = [];
  List<Budget> _budgets = [];
  List<BudgetAlert> _budgetAlerts = [];
  String _currency = '\$';
  bool _isLoading = false;
  String _searchQuery = '';
  
  // Filter variables
  DateTimeRange? _selectedDateRange;
  TransactionType? _selectedTransactionType;
  String? _selectedCategory;
  FilterPeriod _selectedPeriod = FilterPeriod.all;
  
  late AnimationController _animationController;
  late Animation<double> _fabAnimation;
  late _AppLifecycleObserver _lifecycleObserver;
  Timer? _reminderCheckTimer;
  StreamSubscription<String>? _reminderUpdateSubscription;

  final List<Category> _defaultCategories = [
    Category(name: 'Salary', icon: Icons.attach_money, color: Colors.green),
    Category(name: 'Food', icon: Icons.restaurant, color: Colors.orange),
    Category(name: 'Transport', icon: Icons.directions_car, color: Colors.blue),
    Category(name: 'Shopping', icon: Icons.shopping_bag, color: Colors.purple),
    Category(name: 'Entertainment', icon: Icons.movie, color: Colors.red),
    Category(name: 'Bills', icon: Icons.receipt, color: Colors.brown),
    Category(
      name: 'Healthcare',
      icon: Icons.local_hospital,
      color: Colors.pink,
    ),
    Category(name: 'Education', icon: Icons.school, color: Colors.indigo),
    Category(name: 'Other', icon: Icons.category, color: Colors.grey),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    
    _fabAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    
    _animationController.forward();
    
    // Check if app was launched from a notification
    _checkNotificationAppLaunch();
    
    // Set up app lifecycle listener to check for reminder updates
    _lifecycleObserver = _AppLifecycleObserver(onResume: _checkForReminderUpdates);
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    
    // Set up periodic timer to check for reminder updates (every 2 seconds)
    _reminderCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _checkForReminderUpdates();
    });
    
    // Listen to immediate reminder updates
    _reminderUpdateSubscription = ReminderUpdateNotifier.stream.listen(
      (reminderId) {
        print('=== STREAM LISTENER TRIGGERED ===');
        print('Received immediate reminder update for: $reminderId');
        _handleReminderUpdate(reminderId);
      },
      onError: (error) {
        print('ERROR in stream listener: $error');
      },
      onDone: () {
        print('Stream listener completed');
      },
    );
  }
  
  @override
  void dispose() {
    _reminderCheckTimer?.cancel();
    _reminderUpdateSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    _animationController.dispose();
    super.dispose();
  }
  
  // Handle immediate reminder updates from notifications
  Future<void> _handleReminderUpdate(String reminderId) async {
    print('=== HANDLING REMINDER UPDATE ===');
    print('Reminder ID: $reminderId');
    print('Current selected index: $_selectedIndex');
    print('Widget mounted: $mounted');
    
    // Reload reminders from storage
    print('Reloading data...');
    await _loadData();
    print('Data reloaded. Total reminders: ${_reminders.length}');
    
    // Count active and inactive reminders
    final activeCount = _reminders.where((r) => r.isActive).length;
    final inactiveCount = _reminders.where((r) => !r.isActive).length;
    print('Active reminders: $activeCount, Inactive reminders: $inactiveCount');
    
    // Update UI immediately
    if (mounted) {
      print('Calling setState to update UI...');
      setState(() {});
      print('setState called');
      
      // Show a snackbar confirmation if we're on the reminders tab
      if (_selectedIndex == 2) {
        print('Showing snackbar confirmation...');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Reminder marked as done'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      print('Widget not mounted, skipping UI update');
    }
    
    print('=== REMINDER UPDATE COMPLETED ===');
  }

  // Check if any reminders were updated while the app was in background
  Future<void> _checkForReminderUpdates() async {
    final prefs = await SharedPreferences.getInstance();
    final bool? reminderUpdated = prefs.getBool('reminder_updated');
    
    if (reminderUpdated == true) {
      // Clear the flag
      await prefs.setBool('reminder_updated', false);
      
      // Reload reminders
      await _loadData();
      
      // If we're on the reminders tab, refresh the UI
      if (_selectedIndex == 2) {
        setState(() {});
      }
    }
  }
  
  // Check if app was launched from a notification
  Future<void> _checkNotificationAppLaunch() async {
    final notificationAppLaunchDetails = 
        await notifications.FlutterLocalNotificationsPlugin().getNotificationAppLaunchDetails();
        
    if (notificationAppLaunchDetails != null && 
        notificationAppLaunchDetails.didNotificationLaunchApp &&
        notificationAppLaunchDetails.notificationResponse != null) {
      
      // Handle the notification that launched the app
      _handleNotificationResponse(notificationAppLaunchDetails.notificationResponse!);
    }
  }
  
  // Handle notification response
  void _handleNotificationResponse(notifications.NotificationResponse response) {
    if (response.payload != null) {
      try {
        // Try to parse the payload as JSON
        final payloadData = json.decode(response.payload!);
        
        if (payloadData['id'] != null) {
          final reminderId = payloadData['id'];
          
          // Find the reminder
          final reminderIndex = _reminders.indexWhere((r) => r.id == reminderId);
          final reminder = reminderIndex != -1 ? _reminders[reminderIndex] : null;
          
          // Show reminder details
          if (reminder != null) {
            // Navigate to reminders tab
            setState(() {
              _selectedIndex = 2; // Index of Reminders tab
            });
            
            // Show reminder details after a short delay to allow UI to update
            Future.delayed(const Duration(milliseconds: 300), () {
              _showReminderDetails(reminder);
            });
          }
        }
      } catch (e) {
        print('Error handling notification payload: $e');
      }
    }
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final transactions = await DataManager.getTransactions();
      final reminders = await DataManager.getReminders();
      final budgets = await DataManager.getBudgets();
      final budgetAlerts = await DataManager.getBudgetAlerts();
      final currency = await DataManager.getCurrency();
      
      if (mounted) {
        setState(() {
          _transactions = transactions;
          _reminders = reminders;
          _budgets = budgets;
          _budgetAlerts = budgetAlerts;
          _currency = currency;
          _isLoading = false;
        });
      }

      // Reschedule active reminders when app starts
      _rescheduleReminders();
      
      // Check budget status and trigger alerts if needed
      _checkBudgetStatus();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _addTransaction(Transaction transaction) async {
    setState(() {
      _transactions.add(transaction);
    });
    await DataManager.saveTransactions(_transactions);
    
    // Check budget status after adding transaction
    _checkBudgetStatus();
    
    // Show budget impact for expense transactions
    if (transaction.type == TransactionType.expense) {
      _showBudgetImpactMessage(transaction);
    }
  }

  void _updateTransaction(String id, Transaction newTransaction) async {
    setState(() {
      final index = _transactions.indexWhere((t) => t.id == id);
      if (index != -1) {
        _transactions[index] = newTransaction;
      }
    });
    await DataManager.saveTransactions(_transactions);
  }

  void _deleteTransaction(String id) async {
    setState(() {
      _transactions.removeWhere((t) => t.id == id);
    });
    await DataManager.saveTransactions(_transactions);
  }

  void _addReminder(Reminder reminder) async {
    setState(() {
      _reminders.add(reminder);
    });
    await DataManager.saveReminders(_reminders);

    // Check notification permissions before scheduling
    final bool notificationsEnabled = await NotificationService.areNotificationsEnabled();
    if (!notificationsEnabled) {
      // Show settings dialog
      await NotificationService.showNotificationSettingsDialog(context);
      return;
    }

    // Create a payload with reminder information
    final payload = json.encode({
      'id': reminder.id,
      'type': reminder.type.toString(),
      'title': reminder.title,
    });

    try {
      // Schedule notification
      await NotificationService.scheduleNotification(
        id: reminder.id.hashCode,
        title: reminder.title,
        body: reminder.description,
        scheduledDate: reminder.dateTime,
        payload: payload,
      );
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reminder scheduled successfully'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('Error scheduling reminder: $e');
      
      // Show error message and guidance
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to schedule reminder. Check notification settings.'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => NotificationService.showNotificationSettingsDialog(context),
          ),
        ),
      );
    }
  }

  void _updateReminder(String id, Reminder newReminder) async {
    setState(() {
      final index = _reminders.indexWhere((r) => r.id == id);
      if (index != -1) {
        _reminders[index] = newReminder;
      }
    });
    await DataManager.saveReminders(_reminders);

    // Cancel old notification and schedule new one
    await NotificationService.cancelNotification(id.hashCode);
    if (newReminder.isActive) {
      // Create a payload with reminder information
      final payload = json.encode({
        'id': newReminder.id,
        'type': newReminder.type.toString(),
        'title': newReminder.title,
      });
      
      await NotificationService.scheduleNotification(
        id: newReminder.id.hashCode,
        title: newReminder.title,
        body: newReminder.description,
        scheduledDate: newReminder.dateTime,
        payload: payload,
      );
    }
  }

  void _deleteReminder(String id) async {
    setState(() {
      _reminders.removeWhere((r) => r.id == id);
    });
    await DataManager.saveReminders(_reminders);
    await NotificationService.cancelNotification(id.hashCode);
  }

  // Reschedule all active reminders
  Future<void> _rescheduleReminders() async {
    print('Rescheduling ${_reminders.length} reminders');

    // Check if notifications are enabled first
    final bool notificationsEnabled = await NotificationService.areNotificationsEnabled();
    if (!notificationsEnabled) {
      print('Notifications are disabled. Cannot reschedule reminders.');
      return;
    }

    // Cancel all existing notifications first
    await NotificationService.cancelAllNotifications();

    // Add a slight delay before rescheduling to avoid conflicts
    await Future.delayed(const Duration(milliseconds: 500));

    // Request exact alarm permission if on Android
    if (Platform.isAndroid) {
      await NotificationService.requestExactAlarmPermission();
    }

    // Reschedule active reminders
    int scheduledCount = 0;
    int failedCount = 0;
    
    for (final reminder in _reminders) {
      if (reminder.isActive) {
        print('Rescheduling reminder: ${reminder.title} for ${reminder.dateTime}');

        try {
          // Create a payload with reminder information
          final payload = json.encode({
            'id': reminder.id,
            'type': reminder.type.toString(),
            'title': reminder.title,
          });
          
          await NotificationService.scheduleNotification(
            id: reminder.id.hashCode,
            title: reminder.title,
            body: reminder.description,
            scheduledDate: reminder.dateTime,
            payload: payload,
          );
          scheduledCount++;
        } catch (e) {
          print('Failed to reschedule reminder: ${reminder.title}, error: $e');
          failedCount++;
        }
      }
    }

    print('Successfully rescheduled $scheduledCount reminders, $failedCount failed');

    // Show a message to user if some reminders failed to schedule
    if (failedCount > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$failedCount reminders failed to schedule. Check notification settings.'),
          backgroundColor: Colors.orange,
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => NotificationService.showNotificationSettingsDialog(context),
          ),
        ),
      );
    }
  }

  // Budget Management Methods
  void _addBudget(Budget budget) async {
    setState(() {
      _budgets.add(budget);
    });
    await DataManager.saveBudgets(_budgets);
    _checkBudgetStatus();
  }

  void _updateBudget(String id, Budget newBudget) async {
    setState(() {
      final index = _budgets.indexWhere((b) => b.id == id);
      if (index != -1) {
        _budgets[index] = newBudget;
      }
    });
    await DataManager.saveBudgets(_budgets);
    _checkBudgetStatus();
  }

  void _deleteBudget(String id) async {
    setState(() {
      _budgets.removeWhere((b) => b.id == id);
      _budgetAlerts.removeWhere((a) => a.budgetId == id);
    });
    await DataManager.saveBudgets(_budgets);
    await DataManager.saveBudgetAlerts(_budgetAlerts);
  }

  // Check budget status and create alerts
  void _checkBudgetStatus() async {
    final now = DateTime.now();
    List<BudgetAlert> newAlerts = [];

    for (final budget in _budgets.where((b) => b.isActive)) {
      // Skip if budget period hasn't started or has ended
      if (now.isBefore(budget.startDate) || now.isAfter(budget.endDate)) {
        continue;
      }

      final progress = BudgetProgress.calculate(budget, _transactions);
      
      // Check each threshold
      for (final threshold in budget.alertThresholds) {
        if (progress.percentage >= threshold) {
          // Check if we already have an alert for this threshold
          final existingAlert = _budgetAlerts.any((alert) =>
            alert.budgetId == budget.id &&
            alert.threshold == threshold &&
            alert.triggeredAt.isAfter(budget.startDate)
          );

          if (!existingAlert) {
            AlertType alertType;
            String message;
            
            if (threshold >= 100) {
              alertType = AlertType.exceeded;
              message = 'Budget exceeded! You\'ve spent ${NumberFormatter.formatCurrency(progress.spent, _currency)} of ${NumberFormatter.formatCurrency(budget.amount, _currency)} for ${budget.categoryName}.';
            } else if (threshold >= 90) {
              alertType = AlertType.warning;
              message = 'Budget warning! You\'ve used ${threshold.toInt()}% of your ${budget.categoryName} budget.';
            } else {
              alertType = AlertType.approaching;
              message = 'Budget alert: You\'ve used ${threshold.toInt()}% of your ${budget.categoryName} budget.';
            }

            final alert = BudgetAlert(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              budgetId: budget.id,
              type: alertType,
              threshold: threshold,
              triggeredAt: now,
              message: message,
            );

            newAlerts.add(alert);

            // Send notification for budget alerts
            _sendBudgetNotification(alert, budget);
          }
        }
      }
    }

    if (newAlerts.isNotEmpty) {
      setState(() {
        _budgetAlerts.addAll(newAlerts);
      });
      await DataManager.saveBudgetAlerts(_budgetAlerts);
    }
  }

  void _sendBudgetNotification(BudgetAlert alert, Budget budget) async {
    try {
      await NotificationService.showBudgetNotification(
        id: alert.id.hashCode,
        title: 'Budget Alert - ${budget.categoryName}',
        body: alert.message,
      );
    } catch (e) {
      print('Failed to send budget notification: $e');
    }
  }

  void _showBudgetImpactMessage(Transaction transaction) {
    // Find budget for this category
    final budget = _budgets.firstWhere(
      (b) => b.isActive && b.categoryName == transaction.category,
      orElse: () => Budget(
        id: '',
        categoryName: '',
        amount: 0,
        period: BudgetPeriod.monthly,
        startDate: DateTime.now(),
        endDate: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    if (budget.id.isEmpty) {
      // No budget for this category - suggest creating one
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('💡 Consider setting a budget for ${transaction.category} to track your spending!'),
          action: SnackBarAction(
            label: 'CREATE',
            onPressed: () => _showAddBudgetDialog(),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    // Calculate updated progress
    final progress = BudgetProgress.calculate(budget, _transactions);
    
    String message;
    Color backgroundColor;
    IconData icon;

    if (progress.status == BudgetStatus.exceeded) {
      message = '⚠️ You\'ve exceeded your ${transaction.category} budget by ${NumberFormatter.formatCurrency(-progress.remaining, _currency)}';
      backgroundColor = Colors.red;
      icon = Icons.error;
    } else if (progress.status == BudgetStatus.warning) {
      message = '⚠️ You\'ve used ${progress.percentage.toStringAsFixed(0)}% of your ${transaction.category} budget';
      backgroundColor = Colors.orange;
      icon = Icons.warning;
    } else if (progress.status == BudgetStatus.approaching) {
      message = '📊 You\'ve used ${progress.percentage.toStringAsFixed(0)}% of your ${transaction.category} budget';
      backgroundColor = Colors.yellow[700]!;
      icon = Icons.info;
    } else {
      message = '✅ ${NumberFormatter.formatCurrency(progress.remaining, _currency)} remaining in your ${transaction.category} budget';
      backgroundColor = Colors.green;
      icon = Icons.check_circle;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: backgroundColor,
        action: SnackBarAction(
          label: 'VIEW',
          textColor: Colors.white,
          onPressed: () {
            setState(() {
              _selectedIndex = 2; // Navigate to budgets tab
            });
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  List<BudgetProgress> get _budgetProgressList {
    return _budgets
        .where((budget) => budget.isActive)
        .map((budget) => BudgetProgress.calculate(budget, _transactions))
        .toList();
  }

  double get _totalIncome => _transactions
      .where((t) => t.type == TransactionType.income)
      .fold(0, (sum, t) => sum + t.amount);

  double get _totalExpense => _transactions
      .where((t) => t.type == TransactionType.expense)
      .fold(0, (sum, t) => sum + t.amount);

  double get _balance => _totalIncome - _totalExpense;

  List<Transaction> get _filteredTransactions {
    List<Transaction> filtered = List.from(_transactions);
    
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((t) {
        return t.category.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (t.notes?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
                false) ||
            t.amount.toString().contains(_searchQuery);
      }).toList();
    }
    
    // Apply transaction type filter
    if (_selectedTransactionType != null) {
      filtered = filtered.where((t) => t.type == _selectedTransactionType).toList();
    }
    
    // Apply category filter
    if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
      filtered = filtered.where((t) => t.category == _selectedCategory).toList();
    }
    
    // Apply date range filter
    if (_selectedDateRange != null) {
      filtered = filtered.where((t) {
        final transactionDate = DateTime(t.date.year, t.date.month, t.date.day);
        final startDate = DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day);
        final endDate = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day);
        return transactionDate.isAtSameMomentAs(startDate) || 
               transactionDate.isAtSameMomentAs(endDate) ||
               (transactionDate.isAfter(startDate) && transactionDate.isBefore(endDate));
      }).toList();
    }
    
    // Apply period filter
    if (_selectedPeriod != FilterPeriod.all) {
      final now = DateTime.now();
      filtered = filtered.where((t) {
        switch (_selectedPeriod) {
          case FilterPeriod.today:
            return _isSameDay(t.date, now);
          case FilterPeriod.yesterday:
            final yesterday = now.subtract(const Duration(days: 1));
            return _isSameDay(t.date, yesterday);
          case FilterPeriod.thisWeek:
            return _isInCurrentWeek(t.date, now);
          case FilterPeriod.lastWeek:
            final lastWeekStart = now.subtract(Duration(days: now.weekday + 6));
            return _isInWeek(t.date, lastWeekStart);
          case FilterPeriod.thisMonth:
            return t.date.year == now.year && t.date.month == now.month;
          case FilterPeriod.lastMonth:
            final lastMonth = DateTime(now.year, now.month - 1);
            return t.date.year == lastMonth.year && t.date.month == lastMonth.month;
          case FilterPeriod.thisYear:
            return t.date.year == now.year;
          case FilterPeriod.lastYear:
            return t.date.year == now.year - 1;
          case FilterPeriod.all:
          case FilterPeriod.custom:
            return true;
        }
      }).toList();
    }
    
    return filtered;
  }
  
  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year && 
           date1.month == date2.month && 
           date1.day == date2.day;
  }
  
  bool _isInCurrentWeek(DateTime date, DateTime now) {
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    return date.isAfter(startOfWeek.subtract(const Duration(days: 1))) && 
           date.isBefore(endOfWeek.add(const Duration(days: 1)));
  }
  
  bool _isInWeek(DateTime date, DateTime weekStart) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    return date.isAfter(weekStart.subtract(const Duration(days: 1))) && 
           date.isBefore(weekEnd.add(const Duration(days: 1)));
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _buildDashboard(),
      _buildTransactionsList(),
      _buildBudgets(),
      _buildReminders(),
      _buildCategories(),
      _buildSettings(),
    ];

    return LoadingOverlay(
      isLoading: _isLoading,
      loadingMessage: 'Loading your financial data...',
      child: Scaffold(
        body: pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
            
            // Animate the FAB when switching tabs
            if (_selectedIndex == 0 || _selectedIndex == 1 || _selectedIndex == 2 || _selectedIndex == 3) {
              _animationController.reset();
              _animationController.forward();
            }
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Budget',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Alerts',
          ),
          NavigationDestination(
            icon: Icon(Icons.category_outlined),
            selectedIcon: Icon(Icons.category),
            label: 'Tags',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'More',
          ),
        ],
      ),
      floatingActionButton: (_selectedIndex == 0 || _selectedIndex == 1)
          ? ScaleTransition(
              scale: _fabAnimation,
              child: FloatingActionButton(
                onPressed: () => _showAddTransactionDialog(),
                child: const Icon(Icons.add),
              ),
            )
          : _selectedIndex == 2
          ? ScaleTransition(
              scale: _fabAnimation,
              child: FloatingActionButton(
                onPressed: () => _showAddBudgetDialog(),
                child: const Icon(Icons.account_balance_wallet),
              ),
            )
          : _selectedIndex == 3
          ? ScaleTransition(
              scale: _fabAnimation,
              child: FloatingActionButton(
                onPressed: () => _showAddReminderDialog(),
                child: const Icon(Icons.add_alert),
              ),
            )
          : null,
      ),
    );
  }

  Widget _buildDashboard() {
    final recentTransactions = _transactions.reversed.take(5).toList();
    final upcomingReminders =
        _reminders
            .where((r) => r.isActive && r.dateTime.isAfter(DateTime.now()))
            .toList()
          ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () {
              // Profile action
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Profile feature coming soon!')),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadData();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Balance Card
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Balance',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Icon(
                            _balance >= 0 ? Icons.trending_up : Icons.trending_down,
                            color: _balance >= 0 ? Colors.green : Colors.red,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        NumberFormatter.formatCurrency(_balance, _currency),
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              color: _balance >= 0 ? Colors.green : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Income and Expense Cards
              Row(
                children: [
                  Expanded(
                    child: Card(
                      color: Colors.green.withOpacity(0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Income'),
                                Icon(Icons.arrow_downward, color: Colors.green, size: 20),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              NumberFormatter.formatCurrency(_totalIncome, _currency),
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(color: Colors.green),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Card(
                      color: Colors.red.withOpacity(0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Expenses'),
                                Icon(Icons.arrow_upward, color: Colors.red, size: 20),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              NumberFormatter.formatCurrency(_totalExpense, _currency),
                              style: Theme.of(
                                context,
                              ).textTheme.titleLarge?.copyWith(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              // Budget Overview Section
              if (_budgets.where((b) => b.isActive).isNotEmpty) ...[
                const SizedBox(height: 24),
                _sectionHeader('Budget Overview', Icons.account_balance_wallet_outlined),
                const SizedBox(height: 8),
                _buildDashboardBudgetOverview(),
              ],
              
              // Upcoming Reminders Section
              if (upcomingReminders.isNotEmpty) ...[
                const SizedBox(height: 24),
                _sectionHeader('Upcoming Reminders', Icons.notifications_active_outlined),
                const SizedBox(height: 8),
                ...upcomingReminders
                    .take(3)
                    .map(
                      (reminder) => Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _getReminderColor(reminder.type).withOpacity(0.2),
                            child: Icon(
                              _getReminderIcon(reminder.type),
                              color: _getReminderColor(reminder.type),
                              size: 20,
                            ),
                          ),
                          title: Text(reminder.title),
                          subtitle: Text(
                            DateFormat(
                              'MMM dd, yyyy - hh:mm a',
                            ).format(reminder.dateTime),
                          ),
                          trailing: reminder.amount != null
                              ? Text(
                                  NumberFormatter.formatCurrency(reminder.amount!, _currency),
                                  style: Theme.of(context).textTheme.titleMedium,
                                )
                              : null,
                          onTap: () => _showReminderDetails(reminder),
                        ),
                      ),
                    ),
              ],
              const SizedBox(height: 24),
              // Recent Transactions
              _sectionHeader('Recent Transactions', Icons.receipt_long_outlined),
              const SizedBox(height: 16),
              if (recentTransactions.isEmpty)
                Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.receipt_long,
                        size: 48,
                        color: Colors.grey.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No transactions yet',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap + to add your first transaction',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...recentTransactions.map(
                  (transaction) => _buildTransactionTile(transaction),
                ),
              const SizedBox(height: 24),
              // Category Breakdown
              _sectionHeader('Category Breakdown', Icons.pie_chart_outline),
              const SizedBox(height: 16),
              _buildCategoryBreakdown(),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: ThemeManager._getAccentColor()),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ],
    );
  }

  Widget _buildDashboardBudgetOverview() {
    final activeBudgets = _budgets.where((b) => b.isActive).toList();
    final budgetProgressList = _budgetProgressList;
    
    if (activeBudgets.isEmpty) return const SizedBox.shrink();

    // Get budgets that need attention (approaching or over limit)
    final budgetsNeedingAttention = budgetProgressList
        .where((progress) => progress.status != BudgetStatus.safe)
        .take(3)
        .toList();

    return Column(
      children: [
        // Quick budget stats
        Row(
          children: [
            Expanded(
              child: _buildBudgetStatCard(
                'Active Budgets',
                activeBudgets.length.toString(),
                Icons.account_balance_wallet,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildBudgetStatCard(
                'Need Attention',
                budgetsNeedingAttention.length.toString(),
                Icons.warning,
                budgetsNeedingAttention.isEmpty ? Colors.green : Colors.orange,
              ),
            ),
          ],
        ),
        
        // Show budgets that need attention
        if (budgetsNeedingAttention.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...budgetsNeedingAttention.map((progress) {
            final budget = activeBudgets.firstWhere((b) => b.id == progress.budgetId);
            return _buildDashboardBudgetCard(budget, progress);
          }),
        ],
        
        // View all budgets button
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () {
            setState(() {
              _selectedIndex = 2; // Navigate to budgets tab
            });
          },
          icon: const Icon(Icons.arrow_forward),
          label: const Text('View All Budgets'),
        ),
      ],
    );
  }

  Widget _buildBudgetStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardBudgetCard(Budget budget, BudgetProgress progress) {
    Color statusColor;
    IconData statusIcon;
    
    switch (progress.status) {
      case BudgetStatus.safe:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case BudgetStatus.approaching:
        statusColor = Colors.yellow[700]!;
        statusIcon = Icons.warning;
        break;
      case BudgetStatus.warning:
        statusColor = Colors.orange;
        statusIcon = Icons.warning;
        break;
      case BudgetStatus.exceeded:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedIndex = 2; // Navigate to budgets tab
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: statusColor.withOpacity(0.2),
                child: Icon(statusIcon, color: statusColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      budget.categoryName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: progress.percentage / 100,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                      minHeight: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${progress.percentage.toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    NumberFormatter.formatCurrency(progress.remaining, _currency),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: progress.remaining >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryBreakdown() {
    Map<String, double> categoryTotals = {};
    for (var transaction in _transactions) {
      if (transaction.type == TransactionType.expense) {
        categoryTotals[transaction.category] =
            (categoryTotals[transaction.category] ?? 0) + transaction.amount;
      }
    }

    if (categoryTotals.isEmpty) {
      return Center(
        child: Text(
          'No expenses to analyze',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: sortedCategories.map((entry) {
        final percentage = (entry.value / _totalExpense * 100);
        final category = _defaultCategories.firstWhere(
          (c) => c.name == entry.key,
          orElse: () => Category(
            name: entry.key,
            icon: Icons.category,
            color: Colors.grey,
          ),
        );

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(category.icon, color: category.color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(entry.key),
                        Text(NumberFormatter.formatCurrency(entry.value, _currency)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: percentage / 100,
                      backgroundColor: Colors.grey.withOpacity(0.2),
                      valueColor: AlwaysStoppedAnimation(category.color),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('${NumberFormat('#,##0.0').format(percentage)}%'),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTransactionsList() {
    final sortedTransactions = List<Transaction>.from(_filteredTransactions)
      ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _hasActiveFilters() ? Icons.filter_alt : Icons.filter_alt_outlined,
              color: _hasActiveFilters() ? Theme.of(context).primaryColor : null,
            ),
            onPressed: _showFilterDialog,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_hasActiveFilters() ? 170 : 110),
          child: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search transactions...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    filled: true,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
              // Quick filter bar
              _buildQuickFilterBar(),
              // Active filters display
              if (_hasActiveFilters()) _buildActiveFiltersRow(),
            ],
          ),
        ),
      ),
      body: sortedTransactions.isEmpty
          ? Center(
              child: Text(
                _hasActiveFilters() || _searchQuery.isNotEmpty
                    ? 'No transactions found with current filters'
                    : 'No transactions yet',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: sortedTransactions.length,
              itemBuilder: (context, index) {
                return _buildTransactionTile(sortedTransactions[index]);
              },
            ),
    );
  }
  
  bool _hasActiveFilters() {
    return _selectedTransactionType != null ||
           _selectedCategory != null ||
           _selectedDateRange != null ||
           _selectedPeriod != FilterPeriod.all;
  }
  
  Widget _buildActiveFiltersRow() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (_selectedPeriod != FilterPeriod.all)
            _buildFilterChip(
              label: _getPeriodDisplayName(_selectedPeriod),
              onDeleted: () => setState(() => _selectedPeriod = FilterPeriod.all),
            ),
          if (_selectedTransactionType != null)
            _buildFilterChip(
              label: _selectedTransactionType == TransactionType.income ? 'Income' : 'Expense',
              onDeleted: () => setState(() => _selectedTransactionType = null),
            ),
          if (_selectedCategory != null)
            _buildFilterChip(
              label: _selectedCategory!,
              onDeleted: () => setState(() => _selectedCategory = null),
            ),
          if (_selectedDateRange != null)
            _buildFilterChip(
              label: '${DateFormat('MMM dd').format(_selectedDateRange!.start)} - ${DateFormat('MMM dd').format(_selectedDateRange!.end)}',
              onDeleted: () => setState(() => _selectedDateRange = null),
            ),
          if (_hasActiveFilters())
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TextButton.icon(
                onPressed: _clearAllFilters,
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text('Clear All'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildFilterChip({required String label, required VoidCallback onDeleted}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Chip(
        label: Text(label),
        onDeleted: onDeleted,
        deleteIcon: const Icon(Icons.close, size: 16),
        backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
        side: BorderSide(color: Theme.of(context).primaryColor.withOpacity(0.3)),
      ),
    );
  }
  
  String _getPeriodDisplayName(FilterPeriod period) {
    switch (period) {
      case FilterPeriod.all:
        return 'All Time';
      case FilterPeriod.today:
        return 'Today';
      case FilterPeriod.yesterday:
        return 'Yesterday';
      case FilterPeriod.thisWeek:
        return 'This Week';
      case FilterPeriod.lastWeek:
        return 'Last Week';
      case FilterPeriod.thisMonth:
        return 'This Month';
      case FilterPeriod.lastMonth:
        return 'Last Month';
      case FilterPeriod.thisYear:
        return 'This Year';
      case FilterPeriod.lastYear:
        return 'Last Year';
      case FilterPeriod.custom:
        return 'Custom Range';
    }
  }
  
  void _clearAllFilters() {
    setState(() {
      _selectedTransactionType = null;
      _selectedCategory = null;
      _selectedDateRange = null;
      _selectedPeriod = FilterPeriod.all;
    });
  }
  
  Widget _buildQuickFilterBar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildQuickFilterChip('Today', FilterPeriod.today),
          _buildQuickFilterChip('This Week', FilterPeriod.thisWeek),
          _buildQuickFilterChip('This Month', FilterPeriod.thisMonth),
          _buildQuickFilterChip('Income', null, TransactionType.income),
          _buildQuickFilterChip('Expense', null, TransactionType.expense),
        ],
      ),
    );
  }
  
  Widget _buildQuickFilterChip(String label, FilterPeriod? period, [TransactionType? type]) {
    bool isSelected = false;
    
    if (period != null) {
      isSelected = _selectedPeriod == period;
    } else if (type != null) {
      isSelected = _selectedTransactionType == type;
    }
    
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            if (period != null) {
              _selectedPeriod = selected ? period : FilterPeriod.all;
              if (!selected) {
                _selectedDateRange = null;
              }
            } else if (type != null) {
              _selectedTransactionType = selected ? type : null;
            }
          });
        },
      ),
    );
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _FilterBottomSheet(
        selectedPeriod: _selectedPeriod,
        selectedTransactionType: _selectedTransactionType,
        selectedCategory: _selectedCategory,
        selectedDateRange: _selectedDateRange,
        categories: _defaultCategories.map((c) => c.name).toList(),
        onFiltersChanged: (period, type, category, dateRange) {
          setState(() {
            _selectedPeriod = period;
            _selectedTransactionType = type;
            _selectedCategory = category;
            _selectedDateRange = dateRange;
          });
        },
      ),
    );
  }

  Widget _buildTransactionTile(Transaction transaction) {
    final category = _defaultCategories.firstWhere(
      (c) => c.name == transaction.category,
      orElse: () => Category(
        name: transaction.category,
        icon: Icons.category,
        color: Colors.grey,
      ),
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: category.color.withOpacity(0.2),
          child: Icon(category.icon, color: category.color),
        ),
        title: Text(transaction.category),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat('MMM dd, yyyy - hh:mm a').format(transaction.date)),
            if (transaction.notes != null && transaction.notes!.isNotEmpty)
              Text(
                transaction.notes!,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: Text(
          '${transaction.type == TransactionType.income ? '+' : '-'}${NumberFormatter.formatCurrency(transaction.amount, _currency)}',
          style: TextStyle(
            color: transaction.type == TransactionType.income
                ? Colors.green
                : Colors.red,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        onTap: () => _showTransactionDetails(transaction),
      ),
    );
  }

  Widget _buildBudgets() {
    final activeBudgets = _budgets.where((b) => b.isActive).toList();
    final budgetProgressList = _budgetProgressList;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgets'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showBudgetInfoDialog(),
          ),
        ],
      ),
      body: activeBudgets.isEmpty
          ? _buildEmptyBudgetsState()
          : RefreshIndicator(
              onRefresh: () async {
                await _loadData();
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildBudgetOverviewCard(),
                  const SizedBox(height: 16),
                  Text(
                    'Active Budgets',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...budgetProgressList.map((progress) {
                    final budget = _budgets.firstWhere((b) => b.id == progress.budgetId);
                    return _buildBudgetCard(budget, progress);
                  }),
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyBudgetsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Budgets Yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first budget to start\ntracking your spending limits',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showAddBudgetDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Create Budget'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetOverviewCard() {
    final totalBudget = _budgets.where((b) => b.isActive).fold<double>(0, (sum, b) => sum + b.amount);
    final totalSpent = _budgetProgressList.fold<double>(0, (sum, p) => sum + p.spent);
    final totalRemaining = totalBudget - totalSpent;
    final overallPercentage = totalBudget > 0 ? (totalSpent / totalBudget) * 100 : 0;

    Color progressColor;
    if (overallPercentage >= 100) {
      progressColor = Colors.red;
    } else if (overallPercentage >= 90) {
      progressColor = Colors.orange;
    } else if (overallPercentage >= 75) {
      progressColor = Colors.yellow[700]!;
    } else {
      progressColor = Colors.green;
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Budget Overview',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: progressColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: progressColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    '${overallPercentage.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: progressColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: overallPercentage / 100,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              minHeight: 8,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildBudgetSummaryItem(
                  'Total Budget',
                  NumberFormatter.formatCurrency(totalBudget, _currency),
                  Colors.blue,
                ),
                _buildBudgetSummaryItem(
                  'Spent',
                  NumberFormatter.formatCurrency(totalSpent, _currency),
                  Colors.red,
                ),
                _buildBudgetSummaryItem(
                  'Remaining',
                  NumberFormatter.formatCurrency(totalRemaining, _currency),
                  totalRemaining >= 0 ? Colors.green : Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBudgetSummaryItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildBudgetCard(Budget budget, BudgetProgress progress) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (progress.status) {
      case BudgetStatus.safe:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'On Track';
        break;
      case BudgetStatus.approaching:
        statusColor = Colors.yellow[700]!;
        statusIcon = Icons.warning;
        statusText = 'Approaching Limit';
        break;
      case BudgetStatus.warning:
        statusColor = Colors.orange;
        statusIcon = Icons.warning;
        statusText = 'Near Limit';
        break;
      case BudgetStatus.exceeded:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        statusText = 'Over Budget';
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showBudgetDetails(budget, progress),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          budget.categoryName,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getBudgetPeriodText(budget),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Icon(statusIcon, color: statusColor, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress.percentage / 100,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                minHeight: 6,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${NumberFormatter.formatCurrency(progress.spent, _currency)} of ${NumberFormatter.formatCurrency(budget.amount, _currency)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${progress.percentage.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (progress.remaining < 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Text(
                    'Over by ${NumberFormatter.formatCurrency(-progress.remaining, _currency)}',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _getBudgetPeriodText(Budget budget) {
    final formatter = DateFormat('MMM dd');
    switch (budget.period) {
      case BudgetPeriod.weekly:
        return 'Weekly (${formatter.format(budget.startDate)} - ${formatter.format(budget.endDate)})';
      case BudgetPeriod.monthly:
        return 'Monthly (${DateFormat('MMMM yyyy').format(budget.startDate)})';
      case BudgetPeriod.quarterly:
        return 'Quarterly (${formatter.format(budget.startDate)} - ${formatter.format(budget.endDate)})';
      case BudgetPeriod.yearly:
        return 'Yearly (${DateFormat('yyyy').format(budget.startDate)})';
      case BudgetPeriod.custom:
        return 'Custom (${formatter.format(budget.startDate)} - ${formatter.format(budget.endDate)})';
    }
  }

  Widget _buildReminders() {
    final activeReminders = _reminders.where((r) => r.isActive).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    final pastReminders = _reminders.where((r) => !r.isActive).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    return Scaffold(
      appBar: AppBar(title: const Text('Remember'), elevation: 0),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Active', icon: Icon(Icons.alarm_on)),
                Tab(text: 'Past', icon: Icon(Icons.history)),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // Active Reminders
                  activeReminders.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.notifications_off,
                                size: 64,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No active reminders',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tap + to add a reminder',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: activeReminders.length,
                          itemBuilder: (context, index) {
                            return _buildReminderTile(activeReminders[index]);
                          },
                        ),
                  // Past Reminders
                  pastReminders.isEmpty
                      ? Center(
                          child: Text(
                            'No past reminders',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: pastReminders.length,
                          itemBuilder: (context, index) {
                            return _buildReminderTile(pastReminders[index]);
                          },
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReminderTile(Reminder reminder) {
    final isPast = reminder.dateTime.isBefore(DateTime.now());
    final icon = _getReminderIcon(reminder.type);
    final color = _getReminderColor(reminder.type);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(
          reminder.title,
          style: TextStyle(
            decoration: isPast ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reminder.description),
            Text(
              DateFormat('MMM dd, yyyy - hh:mm a').format(reminder.dateTime),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (reminder.amount != null)
              Text(
                NumberFormatter.formatCurrency(reminder.amount!, _currency),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            if (!isPast)
              Text(
                _getTimeRemaining(reminder.dateTime),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        onTap: () => _showReminderDetails(reminder),
      ),
    );
  }

  IconData _getReminderIcon(ReminderType type) {
    switch (type) {
      case ReminderType.billPayment:
        return Icons.receipt_long;
      case ReminderType.salaryReminder:
        return Icons.attach_money;
      case ReminderType.budgetReview:
        return Icons.analytics;
      case ReminderType.subscription:
        return Icons.subscriptions;
      case ReminderType.savingsGoal:
        return Icons.savings;
      case ReminderType.taxPayment:
        return Icons.account_balance;
      case ReminderType.custom:
        return Icons.notifications;
    }
  }

  Color _getReminderColor(ReminderType type) {
    switch (type) {
      case ReminderType.billPayment:
        return Colors.orange;
      case ReminderType.salaryReminder:
        return Colors.green;
      case ReminderType.budgetReview:
        return Colors.blue;
      case ReminderType.subscription:
        return Colors.purple;
      case ReminderType.savingsGoal:
        return Colors.teal;
      case ReminderType.taxPayment:
        return Colors.red;
      case ReminderType.custom:
        return Colors.grey;
    }
  }

  String _getTimeRemaining(DateTime dateTime) {
    final now = DateTime.now();
    final difference = dateTime.difference(now);

    if (difference.inDays > 0) {
      return 'in ${difference.inDays} days';
    } else if (difference.inHours > 0) {
      return 'in ${difference.inHours} hours';
    } else if (difference.inMinutes > 0) {
      return 'in ${difference.inMinutes} minutes';
    } else {
      return 'soon';
    }
  }

  Widget _buildCategories() {
    return Scaffold(
      appBar: AppBar(title: const Text('Categories'), elevation: 0),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _defaultCategories.length,
        itemBuilder: (context, index) {
          final category = _defaultCategories[index];
          final transactionCount = _transactions
              .where((t) => t.category == category.name)
              .length;
          final totalAmount = _transactions
              .where((t) => t.category == category.name)
              .fold(0.0, (sum, t) => sum + t.amount);

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: category.color.withOpacity(0.2),
                child: Icon(category.icon, color: category.color),
              ),
              title: Text(category.name),
              subtitle: Text('$transactionCount transactions'),
              trailing: Text(
                NumberFormatter.formatCurrency(totalAmount, _currency),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSettings() {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), elevation: 0),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Theme Settings
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Appearance',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Theme Mode'),
                  subtitle: Text(_getThemeModeText()),
                  leading: const Icon(Icons.brightness_6),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => _showThemeModeDialog(),
                ),
                ListTile(
                  title: const Text('Accent Color'),
                  subtitle: Text(_getAccentColorText()),
                  leading: CircleAvatar(
                    backgroundColor: _getAccentColor(),
                    radius: 12,
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => _showAccentColorDialog(),
                ),
              ],
            ),
          ),

          // Currency Setting
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: ListTile(
              title: const Text('Currency'),
              subtitle: Text('Current: $_currency'),
              leading: const Icon(Icons.attach_money),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _showCurrencyDialog(),
            ),
          ),

          // Notification Settings
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Notifications',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Check Notification Settings'),
                  subtitle: const Text('Verify notifications work when app is closed'),
                  leading: const Icon(Icons.settings_applications),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => _checkNotificationSettings(),
                ),
                ListTile(
                  title: const Text('Test Notifications'),
                  subtitle: const Text('Send a test notification to verify settings'),
                  leading: const Icon(Icons.notifications_active),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () async {
                    await NotificationService.showTestNotification();

                    // Show confirmation dialog
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Test notification sent'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),

          // Export Data
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: ListTile(
              title: const Text('Export Data'),
              subtitle: const Text('Export transactions as PDF or CSV'),
              leading: const Icon(Icons.download),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _showExportDialog(),
            ),
          ),

          // Clear Data
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: ListTile(
              title: const Text('Clear All Data'),
              subtitle: const Text('Delete all transactions and reminders'),
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _confirmClearData(),
            ),
          ),

          // Version Information
          Card(
            child: ListTile(
              title: const Text('About'),
              subtitle: const Text('Version 2.0.0 - Advanced Budgeting'),
              leading: const Icon(Icons.info_outline),
            ),
          ),
        ],
      ),
    );
  }

  String _getThemeModeText() {
    switch (ThemeManager.themeMode) {
      case ThemeMode.system:
        return 'System Default';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      default:
        return 'System Default';
    }
  }

  String _getAccentColorText() {
    switch (ThemeManager.accentColor) {
      case AccentColor.teal:
        return 'Teal';
      case AccentColor.purple:
        return 'Purple';
      case AccentColor.orange:
        return 'Orange';
      case AccentColor.blue:
        return 'Blue';
      case AccentColor.red:
        return 'Red';
      case AccentColor.green:
        return 'Green';
      case AccentColor.pink:
        return 'Pink';
      case AccentColor.indigo:
        return 'Indigo';
      case AccentColor.cyan:
        return 'Cyan';
      case AccentColor.amber:
        return 'Amber';
      case AccentColor.deepOrange:
        return 'Deep Orange';
      case AccentColor.lightBlue:
        return 'Light Blue';
      case AccentColor.lime:
        return 'Lime';
      case AccentColor.deepPurple:
        return 'Deep Purple';
      case AccentColor.brown:
        return 'Brown';
      case AccentColor.blueGrey:
        return 'Blue Grey';
      case AccentColor.yellow:
        return 'Yellow';
      case AccentColor.lightGreen:
        return 'Light Green';
      case AccentColor.pinkAccent:
        return 'Pink Accent';
      case AccentColor.indigoAccent:
        return 'Indigo Accent';
      default:
        return 'Teal';
    }
  }

  Color _getAccentColor() {
    switch (ThemeManager.accentColor) {
      case AccentColor.teal:
        return Colors.teal;
      case AccentColor.purple:
        return Colors.purple;
      case AccentColor.orange:
        return Colors.orange;
      case AccentColor.blue:
        return Colors.blue;
      case AccentColor.red:
        return Colors.red;
      case AccentColor.green:
        return Colors.green;
      case AccentColor.pink:
        return Colors.pink;
      case AccentColor.indigo:
        return Colors.indigo;
      case AccentColor.cyan:
        return Colors.cyan;
      case AccentColor.amber:
        return Colors.amber;
      case AccentColor.deepOrange:
        return Colors.deepOrange;
      case AccentColor.lightBlue:
        return Colors.lightBlue;
      case AccentColor.lime:
        return Colors.lime;
      case AccentColor.deepPurple:
        return Colors.deepPurple;
      case AccentColor.brown:
        return Colors.brown;
      case AccentColor.blueGrey:
        return Colors.blueGrey;
      case AccentColor.yellow:
        return Colors.yellow;
      case AccentColor.lightGreen:
        return Colors.lightGreen;
      case AccentColor.pinkAccent:
        return Colors.pinkAccent;
      case AccentColor.indigoAccent:
        return Colors.indigoAccent;
      default:
        return Colors.teal;
    }
  }

  void _showThemeModeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Theme Mode'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildThemeOption(
              title: 'Light',
              icon: Icons.light_mode,
              themeMode: ThemeMode.light,
            ),
            _buildThemeOption(
              title: 'Dark',
              icon: Icons.dark_mode,
              themeMode: ThemeMode.dark,
            ),
            _buildThemeOption(
              title: 'System Default',
              icon: Icons.brightness_auto,
              themeMode: ThemeMode.system,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showThemeVariantDialog();
            },
            child: const Text('Theme Styles'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showThemeVariantDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Theme Style'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView(
            children: [
              _buildThemeVariantOption('Standard', Icons.palette, ThemeVariant.standard),
              _buildThemeVariantOption('Vibrant', Icons.color_lens, ThemeVariant.vibrant),
              _buildThemeVariantOption('Minimal', Icons.minimize, ThemeVariant.minimal),
              _buildThemeVariantOption('Neon', Icons.flash_on, ThemeVariant.neon),
              _buildThemeVariantOption('Nature', Icons.eco, ThemeVariant.nature),
              _buildThemeVariantOption('Ocean', Icons.waves, ThemeVariant.ocean),
              _buildThemeVariantOption('Sunset', Icons.wb_sunny, ThemeVariant.sunset),
              _buildThemeVariantOption('Forest', Icons.forest, ThemeVariant.forest),
              _buildThemeVariantOption('Midnight', Icons.nights_stay, ThemeVariant.midnight),
              _buildThemeVariantOption('Rose', Icons.local_florist, ThemeVariant.rose),
              _buildThemeVariantOption('Cosmic', Icons.auto_awesome, ThemeVariant.cosmic),
              _buildThemeVariantOption('Autumn', Icons.park, ThemeVariant.autumn),
              _buildThemeVariantOption('Arctic', Icons.ac_unit, ThemeVariant.arctic),
              _buildThemeVariantOption('Vintage', Icons.camera_alt, ThemeVariant.vintage),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeVariantOption(String title, IconData icon, ThemeVariant variant) {
    final isSelected = ThemeManager.themeVariant == variant;
    
    return ListTile(
      title: Text(title),
      leading: Icon(icon),
      trailing: isSelected ? const Icon(Icons.check, color: Colors.green) : null,
      onTap: () async {
        Navigator.pop(context);
        await ThemeManager.setThemeVariant(variant);
        setState(() {});
      },
    );
  }

  Widget _buildThemeOption({
    required String title,
    required IconData icon,
    required ThemeMode themeMode,
  }) {
    final isSelected = ThemeManager.themeMode == themeMode;
    
    return ListTile(
      title: Text(title),
      leading: Icon(icon),
      trailing: isSelected ? const Icon(Icons.check, color: Colors.green) : null,
      onTap: () async {
        Navigator.pop(context);
        await ThemeManager.setThemeMode(themeMode);
        setState(() {});
      },
    );
  }

  void _showAccentColorDialog() {
    final colorOptions = [
      {'title': 'Teal', 'color': Colors.teal, 'accent': AccentColor.teal},
      {'title': 'Purple', 'color': Colors.purple, 'accent': AccentColor.purple},
      {'title': 'Orange', 'color': Colors.orange, 'accent': AccentColor.orange},
      {'title': 'Blue', 'color': Colors.blue, 'accent': AccentColor.blue},
      {'title': 'Red', 'color': Colors.red, 'accent': AccentColor.red},
      {'title': 'Green', 'color': Colors.green, 'accent': AccentColor.green},
      {'title': 'Pink', 'color': Colors.pink, 'accent': AccentColor.pink},
      {'title': 'Indigo', 'color': Colors.indigo, 'accent': AccentColor.indigo},
      {'title': 'Cyan', 'color': Colors.cyan, 'accent': AccentColor.cyan},
      {'title': 'Amber', 'color': Colors.amber, 'accent': AccentColor.amber},
      {'title': 'Deep Orange', 'color': Colors.deepOrange, 'accent': AccentColor.deepOrange},
      {'title': 'Light Blue', 'color': Colors.lightBlue, 'accent': AccentColor.lightBlue},
      {'title': 'Lime', 'color': Colors.lime, 'accent': AccentColor.lime},
      {'title': 'Deep Purple', 'color': Colors.deepPurple, 'accent': AccentColor.deepPurple},
      {'title': 'Brown', 'color': Colors.brown, 'accent': AccentColor.brown},
      {'title': 'Blue Grey', 'color': Colors.blueGrey, 'accent': AccentColor.blueGrey},
      {'title': 'Yellow', 'color': Colors.yellow, 'accent': AccentColor.yellow},
      {'title': 'Light Green', 'color': Colors.lightGreen, 'accent': AccentColor.lightGreen},
      {'title': 'Pink Accent', 'color': Colors.pinkAccent, 'accent': AccentColor.pinkAccent},
      {'title': 'Indigo Accent', 'color': Colors.indigoAccent, 'accent': AccentColor.indigoAccent},
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Accent Color'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 1,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: colorOptions.length,
            itemBuilder: (context, index) {
              final option = colorOptions[index];
              final isSelected = ThemeManager.accentColor == option['accent'];
              
              return GestureDetector(
                onTap: () async {
                  Navigator.pop(context);
                  await ThemeManager.setAccentColor(option['accent'] as AccentColor);
                  setState(() {});
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: option['color'] as Color,
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected 
                        ? Border.all(color: Colors.white, width: 3)
                        : null,
                    boxShadow: isSelected 
                        ? [BoxShadow(
                            color: (option['color'] as Color).withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          )]
                        : null,
                  ),
                  child: isSelected 
                      ? const Icon(Icons.check, color: Colors.white, size: 24)
                      : null,
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildAccentColorOption({
    required String title,
    required Color color,
    required AccentColor accentColor,
  }) {
    final isSelected = ThemeManager.accentColor == accentColor;
    
    return ListTile(
      title: Text(title),
      leading: CircleAvatar(
        backgroundColor: color,
        radius: 15,
      ),
      trailing: isSelected ? const Icon(Icons.check, color: Colors.green) : null,
      onTap: () async {
        Navigator.pop(context);
        await ThemeManager.setAccentColor(accentColor);
        setState(() {});
      },
    );
  }

  void _confirmClearData() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text(
          'This will delete all transactions and reminders permanently. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              setState(() {
                _transactions.clear();
                _reminders.clear();
              });
              await DataManager.saveTransactions([]);
              await DataManager.saveReminders([]);
              await NotificationService.cancelAllNotifications();
              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('All data cleared')));
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddTransactionDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddTransactionSheet(
        categories: _defaultCategories,
        currency: _currency,
        onAdd: _addTransaction,
      ),
    );
  }

  void _showAddReminderDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _AddReminderSheet(currency: _currency, onAdd: _addReminder),
    );
  }

  void _showAddBudgetDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddBudgetSheet(
        categories: _defaultCategories,
        currency: _currency,
        onAdd: _addBudget,
      ),
    );
  }

  void _showBudgetDetails(Budget budget, BudgetProgress progress) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  budget.categoryName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Progress Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Progress',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _getBudgetStatusColor(progress.status).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _getBudgetStatusColor(progress.status).withOpacity(0.3)),
                          ),
                          child: Text(
                            '${progress.percentage.toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: _getBudgetStatusColor(progress.status),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: progress.percentage / 100,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(_getBudgetStatusColor(progress.status)),
                      minHeight: 8,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildDetailItem('Budget', NumberFormatter.formatCurrency(budget.amount, _currency), Colors.blue),
                        _buildDetailItem('Spent', NumberFormatter.formatCurrency(progress.spent, _currency), Colors.red),
                        _buildDetailItem('Remaining', NumberFormatter.formatCurrency(progress.remaining, _currency), 
                          progress.remaining >= 0 ? Colors.green : Colors.red),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Budget Info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Budget Information',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow('Period', _getBudgetPeriodText(budget)),
                    _buildInfoRow('Transactions', '${progress.transactions.length} transactions'),
                    _buildInfoRow('Daily Average', _calculateDailyAverage(budget, progress)),
                    _buildInfoRow('Status', _getBudgetStatusText(progress.status)),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Smart Insights
            Card(
              color: Theme.of(context).primaryColor.withOpacity(0.05),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline, color: Theme.of(context).primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          'Smart Insights',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._generateBudgetInsights(budget, progress),
                  ],
                ),
              ),
            ),
            
            const Spacer(),
            
            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showEditBudgetDialog(budget);
                    },
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit Budget'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _confirmDeleteBudget(budget.id);
                    },
                    icon: const Icon(Icons.delete),
                    label: const Text('Delete'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  List<Widget> _generateBudgetInsights(Budget budget, BudgetProgress progress) {
    List<Widget> insights = [];
    
    // Calculate days remaining in budget period
    final now = DateTime.now();
    final daysRemaining = budget.endDate.difference(now).inDays;
    final totalDays = budget.endDate.difference(budget.startDate).inDays;
    final daysElapsed = totalDays - daysRemaining;
    
    if (progress.status == BudgetStatus.exceeded) {
      insights.add(_buildInsightItem(
        Icons.error,
        'Budget Exceeded',
        'You\'ve overspent by ${NumberFormatter.formatCurrency(-progress.remaining, _currency)}. Consider reviewing your spending habits.',
        Colors.red,
      ));
    } else if (progress.status == BudgetStatus.warning) {
      insights.add(_buildInsightItem(
        Icons.warning,
        'Approaching Limit',
        'You\'re close to your budget limit with $daysRemaining days remaining. Spend carefully!',
        Colors.orange,
      ));
    } else if (daysRemaining > 0) {
      final dailyBudgetRemaining = progress.remaining / daysRemaining;
      insights.add(_buildInsightItem(
        Icons.info,
        'Daily Budget',
        'You can spend ${NumberFormatter.formatCurrency(dailyBudgetRemaining, _currency)} per day for the remaining $daysRemaining days.',
        Colors.blue,
      ));
    }
    
    // Spending pace insight
    if (daysElapsed > 0 && progress.spent > 0) {
      final dailySpendingRate = progress.spent / daysElapsed;
      final projectedSpending = dailySpendingRate * totalDays;
      
      if (projectedSpending > budget.amount) {
        insights.add(_buildInsightItem(
          Icons.trending_up,
          'Spending Pace',
          'At your current pace, you\'ll exceed your budget by ${NumberFormatter.formatCurrency(projectedSpending - budget.amount, _currency)}.',
          Colors.orange,
        ));
      } else {
        insights.add(_buildInsightItem(
          Icons.trending_down,
          'Good Pace',
          'Your spending pace is on track. You\'re projected to save ${NumberFormatter.formatCurrency(budget.amount - projectedSpending, _currency)}.',
          Colors.green,
        ));
      }
    }
    
    return insights;
  }

  Widget _buildInsightItem(IconData icon, String title, String description, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getBudgetStatusColor(BudgetStatus status) {
    switch (status) {
      case BudgetStatus.safe:
        return Colors.green;
      case BudgetStatus.approaching:
        return Colors.yellow[700]!;
      case BudgetStatus.warning:
        return Colors.orange;
      case BudgetStatus.exceeded:
        return Colors.red;
    }
  }

  String _getBudgetStatusText(BudgetStatus status) {
    switch (status) {
      case BudgetStatus.safe:
        return 'On Track';
      case BudgetStatus.approaching:
        return 'Approaching Limit';
      case BudgetStatus.warning:
        return 'Near Limit';
      case BudgetStatus.exceeded:
        return 'Over Budget';
    }
  }

  String _calculateDailyAverage(Budget budget, BudgetProgress progress) {
    final totalDays = budget.endDate.difference(budget.startDate).inDays;
    final daysElapsed = DateTime.now().difference(budget.startDate).inDays;
    
    if (daysElapsed <= 0) return NumberFormatter.formatCurrency(0, _currency);
    
    final dailyAverage = progress.spent / daysElapsed;
    return NumberFormatter.formatCurrency(dailyAverage, _currency);
  }

  void _showEditBudgetDialog(Budget budget) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddBudgetSheet(
        categories: _defaultCategories,
        currency: _currency,
        onAdd: (newBudget) {
          _updateBudget(budget.id, newBudget);
        },
        budget: budget,
      ),
    );
  }

  void _confirmDeleteBudget(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Budget'),
        content: const Text('Are you sure you want to delete this budget?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _deleteBudget(id);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showBudgetInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Budgets'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Budgets help you control spending by setting limits for each category.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text('• Green: Safe (under 75%)'),
            Text('• Yellow: Approaching limit (75-89%)'),
            Text('• Orange: Near limit (90-99%)'),
            Text('• Red: Over budget (100%+)'),
            SizedBox(height: 12),
            Text(
              'You\'ll receive notifications when approaching your budget limits.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showTransactionDetails(Transaction transaction) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(transaction.category),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${transaction.type == TransactionType.income ? 'Income' : 'Expense'}: ${NumberFormatter.formatCurrency(transaction.amount, _currency)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Date: ${DateFormat('MMMM dd, yyyy - hh:mm a').format(transaction.date)}',
            ),
            if (transaction.notes != null && transaction.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Notes: ${transaction.notes}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showEditTransactionDialog(transaction);
            },
            child: const Text('Edit'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmDelete(transaction.id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showReminderDetails(Reminder reminder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(reminder.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reminder.description),
            const SizedBox(height: 8),
            Text(
              'Date: ${DateFormat('MMMM dd, yyyy - hh:mm a').format(reminder.dateTime)}',
            ),
            if (reminder.amount != null) ...[
              const SizedBox(height: 8),
              Text('Amount: ${NumberFormatter.formatCurrency(reminder.amount!, _currency)}'),
            ],
            const SizedBox(height: 8),
            Text('Type: ${_getReminderTypeName(reminder.type)}'),
            const SizedBox(height: 8),
            Text('Status: ${reminder.isActive ? "Active" : "Completed"}'),
          ],
        ),
        actions: [
          if (reminder.isActive) ...[
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showEditReminderDialog(reminder);
              },
              child: const Text('Edit'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _toggleReminderStatus(reminder);
              },
              child: const Text('Mark as Done'),
            ),
          ],
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmDeleteReminder(reminder.id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _getReminderTypeName(ReminderType type) {
    switch (type) {
      case ReminderType.billPayment:
        return 'Bill Payment';
      case ReminderType.salaryReminder:
        return 'Salary Reminder';
      case ReminderType.budgetReview:
        return 'Budget Review';
      case ReminderType.subscription:
        return 'Subscription';
      case ReminderType.savingsGoal:
        return 'Savings Goal';
      case ReminderType.taxPayment:
        return 'Tax Payment';
      case ReminderType.custom:
        return 'Custom';
    }
  }

  void _toggleReminderStatus(Reminder reminder) {
    final updatedReminder = Reminder(
      id: reminder.id,
      title: reminder.title,
      description: reminder.description,
      dateTime: reminder.dateTime,
      type: reminder.type,
      isActive: false,
      amount: reminder.amount,
    );
    _updateReminder(reminder.id, updatedReminder);
    
    // Notify the stream for immediate UI update
    ReminderUpdateNotifier.notifyReminderUpdated(reminder.id);
    
    // Show a confirmation snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${reminder.title} marked as done'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () {
            // Restore the reminder to active status
            final restoredReminder = Reminder(
              id: reminder.id,
              title: reminder.title,
              description: reminder.description,
              dateTime: reminder.dateTime,
              type: reminder.type,
              isActive: true,
              amount: reminder.amount,
            );
            _updateReminder(reminder.id, restoredReminder);
            // Notify the stream again for the undo action
            ReminderUpdateNotifier.notifyReminderUpdated(reminder.id);
          },
        ),
      ),
    );
  }

  void _showEditTransactionDialog(Transaction transaction) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddTransactionSheet(
        categories: _defaultCategories,
        currency: _currency,
        onAdd: (newTransaction) {
          _updateTransaction(transaction.id, newTransaction);
        },
        transaction: transaction,
      ),
    );
  }

  void _showEditReminderDialog(Reminder reminder) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddReminderSheet(
        currency: _currency,
        onAdd: (newReminder) {
          _updateReminder(reminder.id, newReminder);
        },
        reminder: reminder,
      ),
    );
  }

  void _confirmDelete(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: const Text(
          'Are you sure you want to delete this transaction?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _deleteTransaction(id);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteReminder(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Reminder'),
        content: const Text('Are you sure you want to delete this reminder?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _deleteReminder(id);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showCurrencyDialog() {
    final currencies = ['\$', '€', '£', '¥', '₹', 'R', 'C\$', 'A\$'];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Currency'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: currencies
              .map(
                (currency) => ListTile(
                  title: Text(currency),
                  onTap: () async {
                    setState(() {
                      _currency = currency;
                    });
                    await DataManager.setCurrency(currency);
                    Navigator.pop(context);
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  void _checkNotificationSettings() async {
    final bool notificationsEnabled = await NotificationService.areNotificationsEnabled();
    final bool canScheduleExact = await NotificationService.canScheduleExactNotifications();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notification Status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  notificationsEnabled ? Icons.check_circle : Icons.error,
                  color: notificationsEnabled ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text('Notifications: ${notificationsEnabled ? "Enabled" : "Disabled"}'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  canScheduleExact ? Icons.check_circle : Icons.warning,
                  color: canScheduleExact ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text('Exact Alarms: ${canScheduleExact ? "Allowed" : "Limited"}'),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'For notifications when app is closed:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('1. Enable notifications for this app'),
            const Text('2. Allow "Alarms & reminders" permission'),
            const Text('3. Disable battery optimization'),
            const Text('4. Allow background app refresh'),
            if (!notificationsEnabled) ...[
              const SizedBox(height: 16),
              const Text(
                'Notifications are currently disabled. Please enable them in your device settings.',
                style: TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
        actions: [
          if (!notificationsEnabled)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                NotificationService._openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }



  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Transactions'),
        content: const Text('Choose export format and date range for your transaction statement.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showExportOptionsDialog();
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _showExportOptionsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ExportOptionsSheet(
        transactions: _transactions,
        currency: _currency,
        onExport: (format, dateRange) => _exportData(format, dateRange),
      ),
    );
  }

  Future<void> _exportData(ExportFormat format, DateTimeRange? dateRange) async {
    try {
      // Show downloading notification
      _showExportNotification('Export Started', 'Preparing your transaction statement...');

      // Check if we have transactions to export
      if (_transactions.isEmpty) {
        throw Exception('No transactions to export');
      }

      // Filter transactions by date range if specified
      List<Transaction> transactionsToExport = _transactions;
      if (dateRange != null) {
        transactionsToExport = _transactions.where((t) {
          final transactionDate = DateTime(t.date.year, t.date.month, t.date.day);
          final startDate = DateTime(dateRange.start.year, dateRange.start.month, dateRange.start.day);
          final endDate = DateTime(dateRange.end.year, dateRange.end.month, dateRange.end.day);
          return transactionDate.isAtSameMomentAs(startDate) || 
                 transactionDate.isAtSameMomentAs(endDate) ||
                 (transactionDate.isAfter(startDate) && transactionDate.isBefore(endDate));
        }).toList();
      }

      if (transactionsToExport.isEmpty) {
        throw Exception('No transactions found for the selected date range');
      }

      // Sort transactions by date (oldest first for statement format)
      transactionsToExport.sort((a, b) => a.date.compareTo(b.date));

      String fileName;
      String filePath;

      try {
        if (format == ExportFormat.pdf) {
          fileName = 'ExTrack_Statement_${DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now())}.pdf';
          filePath = await _generatePDFStatement(transactionsToExport, fileName, dateRange);
        } else {
          fileName = 'ExTrack_Statement_${DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now())}.csv';
          filePath = await _generateCSVStatement(transactionsToExport, fileName, dateRange);
        }
      } catch (e) {
        throw Exception('Failed to generate ${format == ExportFormat.pdf ? 'PDF' : 'CSV'}: ${e.toString()}');
      }

      // Show completion notification
      _showExportNotification(
        'Export Complete', 
        'Statement saved as $fileName',
      );

      // Show success dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                const Text('Export Successful'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your transaction statement has been saved as:'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    fileName,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Location: ${filePath.split('/').take(filePath.split('/').length - 1).join('/')}'),
                const SizedBox(height: 8),
                Text('Total transactions: ${transactionsToExport.length}'),
                Text('Format: ${format == ExportFormat.pdf ? 'PDF' : 'CSV'}'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print('Export error: $e');
      
      String errorMessage = e.toString();
      if (errorMessage.contains('MissingPluginException')) {
        errorMessage = 'Permission system not available. File saved to app directory.';
      } else if (errorMessage.contains('Permission denied')) {
        errorMessage = 'Storage permission denied. Please enable storage access in settings.';
      }
      
      _showExportNotification('Export Failed', errorMessage);
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                const SizedBox(width: 8),
                const Text('Export Failed'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Error: $errorMessage'),
                const SizedBox(height: 16),
                if (errorMessage.contains('permission') || errorMessage.contains('Permission'))
                  const Text(
                    'Try:\n• Enable storage permissions in device settings\n• Use a different export location\n• Contact support if the issue persists',
                    style: TextStyle(fontSize: 12),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<String> _generatePDFStatement(List<Transaction> transactions, String fileName, DateTimeRange? dateRange) async {
    final pdf = pw.Document();
    
    // Calculate totals
    double totalIncome = transactions.where((t) => t.type == TransactionType.income).fold(0, (sum, t) => sum + t.amount);
    double totalExpense = transactions.where((t) => t.type == TransactionType.expense).fold(0, (sum, t) => sum + t.amount);
    double balance = totalIncome - totalExpense;
    
    // Calculate running balance
    double runningBalance = 0;
    List<Map<String, dynamic>> transactionData = [];
    
    for (var transaction in transactions) {
      if (transaction.type == TransactionType.income) {
        runningBalance += transaction.amount;
      } else {
        runningBalance -= transaction.amount;
      }
      
      transactionData.add({
        'date': DateFormat('dd/MM/yyyy').format(transaction.date),
        'time': DateFormat('HH:mm').format(transaction.date),
        'description': transaction.category,
        'notes': transaction.notes ?? '',
        'debit': transaction.type == TransactionType.expense ? transaction.amount : 0.0,
        'credit': transaction.type == TransactionType.income ? transaction.amount : 0.0,
        'balance': runningBalance,
      });
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Header
            pw.Container(
              alignment: pw.Alignment.center,
              child: pw.Column(
                children: [
                  pw.Text(
                    'ExTrack - Transaction Statement',
                    style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    dateRange != null 
                        ? 'Period: ${DateFormat('dd/MM/yyyy').format(dateRange.start)} - ${DateFormat('dd/MM/yyyy').format(dateRange.end)}'
                        : 'All Transactions',
                    style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
                  ),
                  pw.Text(
                    'Generated on: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                    style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    'Currency: ${NumberFormatter.getCurrencyName(_currency)}',
                    style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            
            // Summary
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Column(
                    children: [
                      pw.Text('Total Income', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text(NumberFormatter.formatCurrency(totalIncome, _currency), 
                              style: pw.TextStyle(color: PdfColors.green)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text('Total Expense', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text(NumberFormatter.formatCurrency(totalExpense, _currency), 
                              style: pw.TextStyle(color: PdfColors.red)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text('Net Balance', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text(NumberFormatter.formatCurrency(balance, _currency), 
                              style: pw.TextStyle(color: balance >= 0 ? PdfColors.green : PdfColors.red)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            
            // Transaction Table
            pw.Text('Transaction Details', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            
            if (transactions.isEmpty)
              pw.Center(child: pw.Text('No transactions found for the selected period.'))
            else
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: {
                  0: const pw.FixedColumnWidth(60),  // Date
                  1: const pw.FixedColumnWidth(40),  // Time
                  2: const pw.FlexColumnWidth(2),   // Description
                  3: const pw.FlexColumnWidth(2),   // Notes
                  4: const pw.FixedColumnWidth(70), // Debit
                  5: const pw.FixedColumnWidth(70), // Credit
                  6: const pw.FixedColumnWidth(70), // Balance
                },
                children: [
                  // Header row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Date', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Time', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Description', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Notes', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Debit', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Credit', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Balance', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                    ],
                  ),
                  // Data rows
                  ...transactionData.map((data) => pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(data['date'], style: const pw.TextStyle(fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(data['time'], style: const pw.TextStyle(fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(data['description'], style: const pw.TextStyle(fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(data['notes'], style: const pw.TextStyle(fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(
                        data['debit'] > 0 ? NumberFormatter.formatCurrency(data['debit'], _currency) : '-',
                        style: pw.TextStyle(fontSize: 10, color: PdfColors.red),
                      )),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(
                        data['credit'] > 0 ? NumberFormatter.formatCurrency(data['credit'], _currency) : '-',
                        style: pw.TextStyle(fontSize: 10, color: PdfColors.green),
                      )),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(
                        NumberFormatter.formatCurrency(data['balance'], _currency),
                        style: pw.TextStyle(fontSize: 10, color: data['balance'] >= 0 ? PdfColors.green : PdfColors.red),
                      )),
                    ],
                  )),
                ],
              ),
          ];
        },
      ),
    );

    // Save to Downloads folder
    final directory = await _getDownloadsDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(await pdf.save());
    
    return file.path;
  }

  Future<String> _generateCSVStatement(List<Transaction> transactions, String fileName, DateTimeRange? dateRange) async {
    List<List<dynamic>> csvData = [];
    
    // Add header
    csvData.add([
      'Date',
      'Time', 
      'Description',
      'Category',
      'Notes',
      'Debit ($_currency)',
      'Credit ($_currency)',
      'Balance ($_currency)',
      'Transaction Type'
    ]);
    
    // Add currency info row
    csvData.add([
      'Currency: ${NumberFormatter.getCurrencyName(_currency)}',
      '', '', '', '', '', '', '', ''
    ]);
    
    // Calculate running balance and add data rows
    double runningBalance = 0;
    
    for (var transaction in transactions) {
      if (transaction.type == TransactionType.income) {
        runningBalance += transaction.amount;
      } else {
        runningBalance -= transaction.amount;
      }
      
      csvData.add([
        DateFormat('dd/MM/yyyy').format(transaction.date),
        DateFormat('HH:mm:ss').format(transaction.date),
        transaction.category,
        transaction.category,
        transaction.notes ?? '',
        transaction.type == TransactionType.expense ? NumberFormatter.formatCurrency(transaction.amount, _currency) : '',
        transaction.type == TransactionType.income ? NumberFormatter.formatCurrency(transaction.amount, _currency) : '',
        NumberFormatter.formatCurrency(runningBalance, _currency),
        transaction.type == TransactionType.income ? 'Income' : 'Expense',
      ]);
    }
    
    // Add summary rows
    csvData.add([]); // Empty row
    csvData.add(['SUMMARY']);
    csvData.add(['Total Income', '', '', '', '', '', 
                NumberFormatter.formatCurrency(transactions.where((t) => t.type == TransactionType.income).fold(0.0, (sum, t) => sum + t.amount), _currency)]);
    csvData.add(['Total Expense', '', '', '', '', 
                NumberFormatter.formatCurrency(transactions.where((t) => t.type == TransactionType.expense).fold(0.0, (sum, t) => sum + t.amount), _currency)]);
    csvData.add(['Net Balance', '', '', '', '', '', 
                NumberFormatter.formatCurrency(runningBalance, _currency)]);
    csvData.add(['Total Transactions', transactions.length.toString()]);
    csvData.add(['Export Date', DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now())]);
    csvData.add(['Currency Used', _currency]);
    
    if (dateRange != null) {
      csvData.add(['Period', '${DateFormat('dd/MM/yyyy').format(dateRange.start)} - ${DateFormat('dd/MM/yyyy').format(dateRange.end)}']);
    }

    // Convert to CSV string
    String csvString = const ListToCsvConverter().convert(csvData);
    
    // Save to Downloads folder
    final directory = await _getDownloadsDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(csvString);
    
    return file.path;
  }

  Future<Directory> _getDownloadsDirectory() async {
    try {
      if (Platform.isAndroid) {
        // Try multiple Android storage locations
        List<String> possiblePaths = [
          '/storage/emulated/0/Download',
          '/storage/emulated/0/Downloads',
          '/sdcard/Download',
          '/sdcard/Downloads',
        ];
        
        for (String path in possiblePaths) {
          try {
            Directory directory = Directory(path);
            if (await directory.exists()) {
              // Test if we can write to this directory
              final testFile = File('${directory.path}/.test_write');
              await testFile.writeAsString('test');
              await testFile.delete();
              return directory;
            }
          } catch (e) {
            print('Cannot access $path: $e');
            continue;
          }
        }
        
        // Fallback to external storage
        try {
          Directory? directory = await getExternalStorageDirectory();
          if (directory != null) {
            final downloadsDir = Directory('${directory.path}/ExTrack_Exports');
            if (!await downloadsDir.exists()) {
              await downloadsDir.create(recursive: true);
            }
            return downloadsDir;
          }
        } catch (e) {
          print('Cannot access external storage: $e');
        }
        
        // Final fallback to app documents directory
        final appDir = await getApplicationDocumentsDirectory();
        final exportsDir = Directory('${appDir.path}/Exports');
        if (!await exportsDir.exists()) {
          await exportsDir.create(recursive: true);
        }
        return exportsDir;
      }
      
      // For iOS - create exports folder in documents
      final appDir = await getApplicationDocumentsDirectory();
      final exportsDir = Directory('${appDir.path}/Exports');
      if (!await exportsDir.exists()) {
        await exportsDir.create(recursive: true);
      }
      return exportsDir;
    } catch (e) {
      print('Error getting downloads directory: $e');
      // Ultimate fallback
      return await getApplicationDocumentsDirectory();
    }
  }

  void _showExportNotification(String title, String body) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(body),
            ],
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// Export format enum
enum ExportFormat { pdf, csv }

// Export Options Sheet
class _ExportOptionsSheet extends StatefulWidget {
  final List<Transaction> transactions;
  final String currency;
  final Function(ExportFormat, DateTimeRange?) onExport;

  const _ExportOptionsSheet({
    required this.transactions,
    required this.currency,
    required this.onExport,
  });

  @override
  State<_ExportOptionsSheet> createState() => _ExportOptionsSheetState();
}

class _ExportOptionsSheetState extends State<_ExportOptionsSheet> {
  ExportFormat _selectedFormat = ExportFormat.pdf;
  DateTimeRange? _selectedDateRange;
  bool _useCustomRange = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Title
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Export Transaction Statement',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Format Selection
                  Text(
                    'Export Format',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          color: _selectedFormat == ExportFormat.pdf 
                              ? Theme.of(context).primaryColor.withOpacity(0.1)
                              : null,
                          child: InkWell(
                            onTap: () => setState(() => _selectedFormat = ExportFormat.pdf),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.picture_as_pdf,
                                    size: 32,
                                    color: _selectedFormat == ExportFormat.pdf 
                                        ? Theme.of(context).primaryColor
                                        : Colors.grey,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'PDF',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _selectedFormat == ExportFormat.pdf 
                                          ? Theme.of(context).primaryColor
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Professional statement format',
                                    style: Theme.of(context).textTheme.bodySmall,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Card(
                          color: _selectedFormat == ExportFormat.csv 
                              ? Theme.of(context).primaryColor.withOpacity(0.1)
                              : null,
                          child: InkWell(
                            onTap: () => setState(() => _selectedFormat = ExportFormat.csv),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.table_chart,
                                    size: 32,
                                    color: _selectedFormat == ExportFormat.csv 
                                        ? Theme.of(context).primaryColor
                                        : Colors.grey,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'CSV',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _selectedFormat == ExportFormat.csv 
                                          ? Theme.of(context).primaryColor
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Spreadsheet compatible',
                                    style: Theme.of(context).textTheme.bodySmall,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Date Range Selection
                  Text(
                    'Date Range',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  SwitchListTile(
                    title: const Text('Use custom date range'),
                    subtitle: Text(_useCustomRange 
                        ? 'Select specific period for export'
                        : 'Export all transactions'),
                    value: _useCustomRange,
                    onChanged: (value) {
                      setState(() {
                        _useCustomRange = value;
                        if (!value) {
                          _selectedDateRange = null;
                        }
                      });
                    },
                  ),
                  
                  if (_useCustomRange) ...[
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.date_range),
                        title: Text(
                          _selectedDateRange == null
                              ? 'Select Date Range'
                              : '${DateFormat('MMM dd, yyyy').format(_selectedDateRange!.start)} - ${DateFormat('MMM dd, yyyy').format(_selectedDateRange!.end)}',
                        ),
                        trailing: _selectedDateRange != null
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _selectedDateRange = null;
                                  });
                                },
                              )
                            : const Icon(Icons.arrow_forward_ios),
                        onTap: () async {
                          final DateTimeRange? picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            initialDateRange: _selectedDateRange,
                          );
                          if (picked != null) {
                            setState(() {
                              _selectedDateRange = picked;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 24),
                  
                  // Transaction Count Info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context).primaryColor,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Export Summary',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).primaryColor,
                                ),
                              ),
                              Text(
                                _getExportSummary(),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Export Button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onExport(_selectedFormat, _useCustomRange ? _selectedDateRange : null);
                },
                icon: Icon(_selectedFormat == ExportFormat.pdf ? Icons.picture_as_pdf : Icons.table_chart),
                label: Text('Export as ${_selectedFormat == ExportFormat.pdf ? 'PDF' : 'CSV'}'),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  String _getExportSummary() {
    List<Transaction> transactionsToExport = widget.transactions;
    
    if (_useCustomRange && _selectedDateRange != null) {
      transactionsToExport = widget.transactions.where((t) {
        final transactionDate = DateTime(t.date.year, t.date.month, t.date.day);
        final startDate = DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day);
        final endDate = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day);
        return transactionDate.isAtSameMomentAs(startDate) || 
               transactionDate.isAtSameMomentAs(endDate) ||
               (transactionDate.isAfter(startDate) && transactionDate.isBefore(endDate));
      }).toList();
    }
    
    final totalIncome = transactionsToExport.where((t) => t.type == TransactionType.income).fold(0.0, (sum, t) => sum + t.amount);
    final totalExpense = transactionsToExport.where((t) => t.type == TransactionType.expense).fold(0.0, (sum, t) => sum + t.amount);
    
    return '${transactionsToExport.length} transactions\n'
           'Income: ${widget.currency}${NumberFormatter.formatNumber(totalIncome)}\n'
           'Expense: ${widget.currency}${NumberFormatter.formatNumber(totalExpense)}';
  }
}

// Filter Bottom Sheet
class _FilterBottomSheet extends StatefulWidget {
  final FilterPeriod selectedPeriod;
  final TransactionType? selectedTransactionType;
  final String? selectedCategory;
  final DateTimeRange? selectedDateRange;
  final List<String> categories;
  final Function(FilterPeriod, TransactionType?, String?, DateTimeRange?) onFiltersChanged;

  const _FilterBottomSheet({
    required this.selectedPeriod,
    required this.selectedTransactionType,
    required this.selectedCategory,
    required this.selectedDateRange,
    required this.categories,
    required this.onFiltersChanged,
  });

  @override
  State<_FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<_FilterBottomSheet> {
  late FilterPeriod _period;
  TransactionType? _transactionType;
  String? _category;
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    _period = widget.selectedPeriod;
    _transactionType = widget.selectedTransactionType;
    _category = widget.selectedCategory;
    _dateRange = widget.selectedDateRange;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Title
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filter Transactions',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _period = FilterPeriod.all;
                      _transactionType = null;
                      _category = null;
                      _dateRange = null;
                    });
                  },
                  child: const Text('Clear All'),
                ),
              ],
            ),
          ),
          
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Time Period Section
                  _buildSectionTitle('Time Period'),
                  _buildPeriodSelector(),
                  
                  const SizedBox(height: 24),
                  
                  // Transaction Type Section
                  _buildSectionTitle('Transaction Type'),
                  _buildTransactionTypeSelector(),
                  
                  const SizedBox(height: 24),
                  
                  // Category Section
                  _buildSectionTitle('Category'),
                  _buildCategorySelector(),
                  
                  const SizedBox(height: 24),
                  
                  // Custom Date Range Section
                  if (_period == FilterPeriod.custom) ...[
                    _buildSectionTitle('Custom Date Range'),
                    _buildDateRangeSelector(),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
          ),
          
          // Apply Button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  widget.onFiltersChanged(_period, _transactionType, _category, _dateRange);
                  Navigator.pop(context);
                },
                child: const Text('Apply Filters'),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
  
  Widget _buildPeriodSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: FilterPeriod.values.map((period) {
        final isSelected = _period == period;
        return FilterChip(
          label: Text(_getPeriodDisplayName(period)),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              _period = period;
              if (period != FilterPeriod.custom) {
                _dateRange = null;
              }
            });
          },
        );
      }).toList(),
    );
  }
  
  Widget _buildTransactionTypeSelector() {
    return Row(
      children: [
        Expanded(
          child: FilterChip(
            label: const Text('All'),
            selected: _transactionType == null,
            onSelected: (selected) {
              setState(() {
                _transactionType = null;
              });
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilterChip(
            label: const Text('Income'),
            selected: _transactionType == TransactionType.income,
            onSelected: (selected) {
              setState(() {
                _transactionType = selected ? TransactionType.income : null;
              });
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilterChip(
            label: const Text('Expense'),
            selected: _transactionType == TransactionType.expense,
            onSelected: (selected) {
              setState(() {
                _transactionType = selected ? TransactionType.expense : null;
              });
            },
          ),
        ),
      ],
    );
  }
  
  Widget _buildCategorySelector() {
    return Column(
      children: [
        // All categories option
        SizedBox(
          width: double.infinity,
          child: FilterChip(
            label: const Text('All Categories'),
            selected: _category == null,
            onSelected: (selected) {
              setState(() {
                _category = null;
              });
            },
          ),
        ),
        const SizedBox(height: 8),
        // Individual categories
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.categories.map((category) {
            final isSelected = _category == category;
            return FilterChip(
              label: Text(category),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _category = selected ? category : null;
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }
  
  Widget _buildDateRangeSelector() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.date_range),
        title: Text(
          _dateRange == null
              ? 'Select Date Range'
              : '${DateFormat('MMM dd, yyyy').format(_dateRange!.start)} - ${DateFormat('MMM dd, yyyy').format(_dateRange!.end)}',
        ),
        trailing: _dateRange != null
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  setState(() {
                    _dateRange = null;
                  });
                },
              )
            : const Icon(Icons.arrow_forward_ios),
        onTap: () async {
          final DateTimeRange? picked = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2020),
            lastDate: DateTime.now(),
            initialDateRange: _dateRange,
          );
          if (picked != null) {
            setState(() {
              _dateRange = picked;
            });
          }
        },
      ),
    );
  }
  
  String _getPeriodDisplayName(FilterPeriod period) {
    switch (period) {
      case FilterPeriod.all:
        return 'All Time';
      case FilterPeriod.today:
        return 'Today';
      case FilterPeriod.yesterday:
        return 'Yesterday';
      case FilterPeriod.thisWeek:
        return 'This Week';
      case FilterPeriod.lastWeek:
        return 'Last Week';
      case FilterPeriod.thisMonth:
        return 'This Month';
      case FilterPeriod.lastMonth:
        return 'Last Month';
      case FilterPeriod.thisYear:
        return 'This Year';
      case FilterPeriod.lastYear:
        return 'Last Year';
      case FilterPeriod.custom:
        return 'Custom Range';
    }
  }
}

// Add Transaction Sheet
class _AddTransactionSheet extends StatefulWidget {
  final List<Category> categories;
  final String currency;
  final Function(Transaction) onAdd;
  final Transaction? transaction;

  const _AddTransactionSheet({
    required this.categories,
    required this.currency,
    required this.onAdd,
    this.transaction,
  });

  @override
  State<_AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<_AddTransactionSheet> {
  late TextEditingController _amountController;
  late TextEditingController _notesController;
  late String _selectedCategory;
  late TransactionType _selectedType;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.transaction?.amount.toString() ?? '',
    );
    _notesController = TextEditingController(
      text: widget.transaction?.notes ?? '',
    );
    _selectedCategory =
        widget.transaction?.category ?? widget.categories.first.name;
    _selectedType = widget.transaction?.type ?? TransactionType.expense;
    _selectedDate = widget.transaction?.date ?? DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.transaction == null
                  ? 'Add Transaction'
                  : 'Edit Transaction',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            // Type Selector
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(
                  value: TransactionType.income,
                  label: Text('Income'),
                  icon: Icon(Icons.arrow_downward),
                ),
                ButtonSegment(
                  value: TransactionType.expense,
                  label: Text('Expense'),
                  icon: Icon(Icons.arrow_upward),
                ),
              ],
              selected: {_selectedType},
              onSelectionChanged: (Set<TransactionType> newSelection) {
                setState(() {
                  _selectedType = newSelection.first;
                });
              },
            ),
            const SizedBox(height: 16),
            // Amount Input
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: widget.currency,
                border: const OutlineInputBorder(),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
            ),
            const SizedBox(height: 16),
            // Category Dropdown
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: widget.categories
                  .map(
                    (category) => DropdownMenuItem(
                      value: category.name,
                      child: Row(
                        children: [
                          Icon(category.icon, color: category.color, size: 20),
                          const SizedBox(width: 8),
                          Text(category.name),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCategory = value!;
                });
              },
            ),
            const SizedBox(height: 16),
            // Date Picker
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text(
                DateFormat('MMMM dd, yyyy - hh:mm a').format(_selectedDate),
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(_selectedDate),
                  );
                  if (time != null) {
                    setState(() {
                      _selectedDate = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  }
                }
              },
            ),
            const SizedBox(height: 16),
            // Notes Input
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (Optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final amount = double.tryParse(_amountController.text);
                    if (amount == null || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter a valid amount'),
                        ),
                      );
                      return;
                    }

                    final transaction = Transaction(
                      id:
                          widget.transaction?.id ??
                          DateTime.now().millisecondsSinceEpoch.toString(),
                      amount: amount,
                      category: _selectedCategory,
                      date: _selectedDate,
                      notes: _notesController.text.isEmpty
                          ? null
                          : _notesController.text,
                      type: _selectedType,
                    );

                    widget.onAdd(transaction);
                    Navigator.pop(context);
                  },
                  child: Text(widget.transaction == null ? 'Add' : 'Update'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }
}

// Add Reminder Sheet
class _AddReminderSheet extends StatefulWidget {
  final String currency;
  final Function(Reminder) onAdd;
  final Reminder? reminder;

  const _AddReminderSheet({
    required this.currency,
    required this.onAdd,
    this.reminder,
  });

  @override
  State<_AddReminderSheet> createState() => _AddReminderSheetState();
}

class _AddReminderSheetState extends State<_AddReminderSheet> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _amountController;
  late ReminderType _selectedType;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  bool _includeAmount = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.reminder?.title ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.reminder?.description ?? '',
    );
    _amountController = TextEditingController(
      text: widget.reminder?.amount?.toString() ?? '',
    );
    _selectedType = widget.reminder?.type ?? ReminderType.billPayment;
    _selectedDate = widget.reminder?.dateTime ?? DateTime.now();
    _selectedTime = TimeOfDay.fromDateTime(
      widget.reminder?.dateTime ?? DateTime.now(),
    );
    _includeAmount = widget.reminder?.amount != null;

    // Set default title based on type
    if (widget.reminder == null) {
      _updateDefaultTitle();
    }
  }

  void _updateDefaultTitle() {
    switch (_selectedType) {
      case ReminderType.billPayment:
        _titleController.text = 'Pay Bill';
        break;
      case ReminderType.salaryReminder:
        _titleController.text = 'Salary Day';
        break;
      case ReminderType.budgetReview:
        _titleController.text = 'Review Budget';
        break;
      case ReminderType.subscription:
        _titleController.text = 'Subscription Renewal';
        break;
      case ReminderType.savingsGoal:
        _titleController.text = 'Savings Goal';
        break;
      case ReminderType.taxPayment:
        _titleController.text = 'Tax Payment Due';
        break;
      case ReminderType.custom:
        _titleController.text = '';
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.reminder == null ? 'Add Reminder' : 'Edit Reminder',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              // Type Selector
              DropdownButtonFormField<ReminderType>(
                value: _selectedType,
                decoration: const InputDecoration(
                  labelText: 'Reminder Type',
                  border: OutlineInputBorder(),
                ),
                items: ReminderType.values
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(_getReminderTypeName(type)),
                      ),
                    )
                    .toList(),
                onChanged: widget.reminder == null
                    ? (value) {
                        setState(() {
                          _selectedType = value!;
                          _updateDefaultTitle();
                        });
                      }
                    : null,
              ),
              const SizedBox(height: 16),
              // Title Input
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // Description Input
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              // Date and Time Pickers
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Date'),
                      subtitle: Text(
                        DateFormat('MMM dd, yyyy').format(_selectedDate),
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (date != null) {
                          setState(() {
                            _selectedDate = date;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Time'),
                      subtitle: Text(_selectedTime.format(context)),
                      trailing: const Icon(Icons.access_time),
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: _selectedTime,
                        );
                        if (time != null) {
                          setState(() {
                            _selectedTime = time;
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Amount Toggle
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include Amount'),
                value: _includeAmount,
                onChanged: (value) {
                  setState(() {
                    _includeAmount = value;
                  });
                },
              ),
              if (_includeAmount) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    prefixText: widget.currency,
                    border: const OutlineInputBorder(),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      if (_titleController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a title')),
                        );
                        return;
                      }

                      double? amount;
                      if (_includeAmount) {
                        amount = double.tryParse(_amountController.text);
                        if (amount == null || amount <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a valid amount'),
                            ),
                          );
                          return;
                        }
                      }

                      final reminderDateTime = DateTime(
                        _selectedDate.year,
                        _selectedDate.month,
                        _selectedDate.day,
                        _selectedTime.hour,
                        _selectedTime.minute,
                      );

                      final reminder = Reminder(
                        id:
                            widget.reminder?.id ??
                            DateTime.now().millisecondsSinceEpoch.toString(),
                        title: _titleController.text,
                        description: _descriptionController.text,
                        dateTime: reminderDateTime,
                        type: _selectedType,
                        isActive: true,
                        amount: amount,
                      );

                      widget.onAdd(reminder);
                      Navigator.pop(context);
                    },
                    child: Text(widget.reminder == null ? 'Add' : 'Update'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getReminderTypeName(ReminderType type) {
    switch (type) {
      case ReminderType.billPayment:
        return 'Bill Payment';
      case ReminderType.salaryReminder:
        return 'Salary Reminder';
      case ReminderType.budgetReview:
        return 'Budget Review';
      case ReminderType.subscription:
        return 'Subscription';
      case ReminderType.savingsGoal:
        return 'Savings Goal';
      case ReminderType.taxPayment:
        return 'Tax Payment';
      case ReminderType.custom:
        return 'Custom';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }
}

// Add Budget Sheet
class _AddBudgetSheet extends StatefulWidget {
  final List<Category> categories;
  final String currency;
  final Function(Budget) onAdd;
  final Budget? budget;

  const _AddBudgetSheet({
    required this.categories,
    required this.currency,
    required this.onAdd,
    this.budget,
  });

  @override
  State<_AddBudgetSheet> createState() => _AddBudgetSheetState();
}

class _AddBudgetSheetState extends State<_AddBudgetSheet> {
  late TextEditingController _amountController;
  String _selectedCategory = '';
  BudgetPeriod _selectedPeriod = BudgetPeriod.monthly;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 30));
  List<double> _alertThresholds = [50.0, 75.0, 90.0, 100.0];

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    
    if (widget.budget != null) {
      // Editing existing budget
      _amountController.text = widget.budget!.amount.toString();
      _selectedCategory = widget.budget!.categoryName;
      _selectedPeriod = widget.budget!.period;
      _startDate = widget.budget!.startDate;
      _endDate = widget.budget!.endDate;
      _alertThresholds = List.from(widget.budget!.alertThresholds);
    } else {
      // Creating new budget
      _selectedCategory = widget.categories.first.name;
      _calculateEndDate();
    }
  }

  void _calculateEndDate() {
    switch (_selectedPeriod) {
      case BudgetPeriod.weekly:
        _endDate = _startDate.add(const Duration(days: 7));
        break;
      case BudgetPeriod.monthly:
        _endDate = DateTime(_startDate.year, _startDate.month + 1, _startDate.day);
        break;
      case BudgetPeriod.quarterly:
        _endDate = DateTime(_startDate.year, _startDate.month + 3, _startDate.day);
        break;
      case BudgetPeriod.yearly:
        _endDate = DateTime(_startDate.year + 1, _startDate.month, _startDate.day);
        break;
      case BudgetPeriod.custom:
        // Keep current end date for custom period
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.budget != null ? 'Edit Budget' : 'Create Budget'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            TextButton(
              onPressed: _saveBudget,
              child: const Text('Save'),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Category'),
              _buildCategorySelector(),
              const SizedBox(height: 24),
              
              _buildSectionTitle('Budget Amount'),
              _buildAmountInput(),
              const SizedBox(height: 24),
              
              _buildSectionTitle('Budget Period'),
              _buildPeriodSelector(),
              const SizedBox(height: 24),
              
              if (_selectedPeriod == BudgetPeriod.custom) ...[
                _buildSectionTitle('Custom Date Range'),
                _buildDateRangeSelector(),
                const SizedBox(height: 24),
              ],
              
              _buildSectionTitle('Alert Thresholds'),
              _buildAlertThresholdSelector(),
              const SizedBox(height: 24),
              
              _buildBudgetPreview(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildCategorySelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select Category'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.categories.map((category) {
                final isSelected = _selectedCategory == category.name;
                return FilterChip(
                  label: Text(category.name),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedCategory = category.name;
                    });
                  },
                  avatar: Icon(
                    category.icon,
                    size: 18,
                    color: isSelected ? Colors.white : category.color,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountInput() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Budget Amount',
            prefixText: widget.currency,
            border: const OutlineInputBorder(),
            hintText: 'Enter budget amount',
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Budget Period'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: BudgetPeriod.values.map((period) {
                final isSelected = _selectedPeriod == period;
                return FilterChip(
                  label: Text(_getPeriodName(period)),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedPeriod = period;
                      if (period != BudgetPeriod.custom) {
                        _calculateEndDate();
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangeSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              title: const Text('Start Date'),
              subtitle: Text(DateFormat('MMM dd, yyyy').format(_startDate)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _startDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (date != null) {
                  setState(() {
                    _startDate = date;
                  });
                }
              },
            ),
            const Divider(),
            ListTile(
              title: const Text('End Date'),
              subtitle: Text(DateFormat('MMM dd, yyyy').format(_endDate)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _endDate,
                  firstDate: _startDate,
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (date != null) {
                  setState(() {
                    _endDate = date;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertThresholdSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Get notified when you reach:'),
            const SizedBox(height: 12),
            ...['50%', '75%', '90%', '100%'].asMap().entries.map((entry) {
              final index = entry.key;
              final label = entry.value;
              final threshold = [50.0, 75.0, 90.0, 100.0][index];
              final isEnabled = _alertThresholds.contains(threshold);
              
              return CheckboxListTile(
                title: Text(label),
                subtitle: Text(_getThresholdDescription(threshold)),
                value: isEnabled,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      if (!_alertThresholds.contains(threshold)) {
                        _alertThresholds.add(threshold);
                        _alertThresholds.sort();
                      }
                    } else {
                      _alertThresholds.remove(threshold);
                    }
                  });
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildBudgetPreview() {
    final amount = double.tryParse(_amountController.text) ?? 0;
    if (amount <= 0) return const SizedBox.shrink();

    return Card(
      color: Theme.of(context).primaryColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Budget Preview',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Category:'),
                Text(_selectedCategory, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Amount:'),
                Text(
                  NumberFormatter.formatCurrency(amount, widget.currency),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Period:'),
                Text(_getPeriodName(_selectedPeriod), style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Duration:'),
                Text(
                  '${DateFormat('MMM dd').format(_startDate)} - ${DateFormat('MMM dd').format(_endDate)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getPeriodName(BudgetPeriod period) {
    switch (period) {
      case BudgetPeriod.weekly:
        return 'Weekly';
      case BudgetPeriod.monthly:
        return 'Monthly';
      case BudgetPeriod.quarterly:
        return 'Quarterly';
      case BudgetPeriod.yearly:
        return 'Yearly';
      case BudgetPeriod.custom:
        return 'Custom';
    }
  }

  String _getThresholdDescription(double threshold) {
    switch (threshold) {
      case 50.0:
        return 'Halfway through your budget';
      case 75.0:
        return 'Approaching your limit';
      case 90.0:
        return 'Near your budget limit';
      case 100.0:
        return 'Budget limit reached';
      default:
        return '';
    }
  }

  void _saveBudget() {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid budget amount')),
      );
      return;
    }

    if (_selectedCategory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }

    if (_endDate.isBefore(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date must be after start date')),
      );
      return;
    }

    final budget = Budget(
      id: widget.budget?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      categoryName: _selectedCategory,
      amount: amount,
      period: _selectedPeriod,
      startDate: _startDate,
      endDate: _endDate,
      alertThresholds: _alertThresholds,
      createdAt: widget.budget?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    widget.onAdd(budget);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }
}