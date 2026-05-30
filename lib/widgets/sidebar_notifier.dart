// lib/widgets/sidebar_notifier.dart
//
// Global ValueNotifier for the desktop sidebar's collapsed/expanded
// preference. Persisted via SharedPreferences — the SAME storage layer
// theme_notifier uses, NOT raw browser localStorage (which is unreliable in
// this Flutter Web setup). Mirrors ThemeNotifier's shape so the persistence
// pattern stays consistent across UI prefs.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global singleton — import and use directly (like [themeNotifier]).
final sidebarNotifier = SidebarNotifier();

class SidebarNotifier extends ValueNotifier<bool> {
  static const _key = 'sidebar_collapsed';

  /// Default expanded (false) — first run shows the full labelled nav.
  SidebarNotifier() : super(false);

  /// Restore the saved preference. Call once at startup (before runApp),
  /// alongside themeNotifier.load().
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    value = prefs.getBool(_key) ?? false;
  }

  /// Flip collapsed ⇄ expanded and persist.
  Future<void> toggle() => setCollapsed(!value);

  /// Set the collapsed state explicitly and persist it.
  Future<void> setCollapsed(bool collapsed) async {
    value = collapsed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, collapsed);
  }

  bool get isCollapsed => value;
}
