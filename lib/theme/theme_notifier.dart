// lib/theme/theme_notifier.dart
// Global ValueNotifier that persists day/night mode via SharedPreferences.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global singleton — import and use directly.
final themeNotifier = ThemeNotifier();

class ThemeNotifier extends ValueNotifier<ThemeMode> {
  static const _key = 'theme_mode';

  ThemeNotifier() : super(ThemeMode.light);

  /// Call once at app startup (before runApp) to restore saved preference.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    value = (prefs.getString(_key) == 'night')
        ? ThemeMode.dark
        : ThemeMode.light;
  }

  /// Toggle between day and night, persisting the choice.
  Future<void> toggle() async {
    final next =
        (value == ThemeMode.dark) ? ThemeMode.light : ThemeMode.dark;
    value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, next == ThemeMode.dark ? 'night' : 'day');
  }

  bool get isNight => value == ThemeMode.dark;
}
