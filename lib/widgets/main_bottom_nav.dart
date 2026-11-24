import 'package:flutter/material.dart';
import 'dart:ui';
import '../core/theme/app_theme.dart';

class MainBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const MainBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.only(left: 20, right: 20, bottom: 24),
        decoration: BoxDecoration(
          color: isDark 
              ? const Color(0xFF1A1D24).withOpacity(0.85) 
              : Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.5),
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: BottomNavigationBar(
              currentIndex: currentIndex,
              onTap: onTap,
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.transparent,
              elevation: 0,
              showSelectedLabels: false,
              showUnselectedLabels: false,

              selectedItemColor: const Color(0xFF2D6A4F), // Premium Green
              unselectedItemColor: isDark ? Colors.white38 : Colors.black38,

              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_rounded),
                  label: 'Ana Sayfa',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.search_rounded),
                  label: 'Keşfet',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.add_circle_rounded, size: 40),
                  label: 'Ekle',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.favorite_border_rounded),
                  label: 'Beğeniler',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person_rounded),
                  label: 'Profil',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
