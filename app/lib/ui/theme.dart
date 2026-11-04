import 'package:flutter/material.dart';

import '../features/web3d/web_painter.dart' show kBlue, kCrimson;

export '../features/web3d/web_painter.dart' show kBlue, kCrimson;

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: kBlue, brightness: b).copyWith(
    primary: dark ? kBlue : const Color(0xFF0A7FC4),
    secondary: kCrimson,
    surface: dark ? const Color(0xFF0B0F1E) : Colors.white,
  );
  final base = ThemeData(brightness: b, colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: dark ? const Color(0xFF03040A) : const Color(0xFFF2F5FC),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      color: dark ? const Color(0xFF0B0F1E) : Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.08))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.onSurface.withValues(alpha: 0.06),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF080B16) : Colors.white,
      indicatorColor: scheme.primary.withValues(alpha: 0.2),
      height: 66,
    ),
    chipTheme: base.chipTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

String fmtDue(DateTime? d, {DateTime? now}) {
  if (d == null) return 'No date';
  final n = now ?? DateTime.now();
  final l = d.toLocal();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(l.year, l.month, l.day);
  final diff = day.difference(today).inDays;
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final time = '$h:${l.minute.toString().padLeft(2, '0')} ${l.hour < 12 ? 'AM' : 'PM'}';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final label = diff == 0 ? 'Today' : diff == 1 ? 'Tomorrow' : diff == -1 ? 'Yesterday' : '${m[l.month - 1]} ${l.day}';
  return '$label, $time';
}
