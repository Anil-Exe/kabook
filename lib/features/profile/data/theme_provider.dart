import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// SharedPreferences örneğini taşıyacak provider
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError();
});

class ThemeNotifier extends StateNotifier<ThemeMode> {
  final SharedPreferences prefs;

  ThemeNotifier(this.prefs) : super(ThemeMode.system) {
    _loadTheme();
  }

  void _loadTheme() {
    final savedTheme = prefs.getString('themeMode');
    if (savedTheme == 'light') state = ThemeMode.light;
    else if (savedTheme == 'dark') state = ThemeMode.dark;
    else state = ThemeMode.system;
  }

  void toggleTheme() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    prefs.setString('themeMode', state == ThemeMode.dark ? 'dark' : 'light');
  }
}

final themeModeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemeNotifier(prefs);
});