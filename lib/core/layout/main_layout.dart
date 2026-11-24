import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_providers.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/events/presentation/pages/events_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/notifications/presentation/widgets/notification_badge.dart';
import '../../features/home/presentation/pages/reels_page.dart'; // 🆕 Eklendi

import '../pages/qr_page.dart';
import '../pages/help_page.dart';

class MainLayout extends ConsumerStatefulWidget {
  const MainLayout({super.key});

  @override
  ConsumerState<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends ConsumerState<MainLayout> {
  int _currentIndex = 0;

  void _onItemTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUserAsync = ref.watch(currentUserProvider);
    final theme = Theme.of(context);
    // final isDark = theme.brightness == Brightness.dark;

    final List<Widget> pages = [
      const HomePage(),
      const EventsPage(), // 2. Sıra
      const ReelsPage(),  // 3. Sıra (ORTA)
      const HelpPage(),
      currentUserAsync.when(
        data: (user) => user != null
            ? ProfilePage(userId: user.$id)
            : const Center(child: CircularProgressIndicator()),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Hata oluştu')),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () {
            if (_currentIndex == 0) {
              // TODO: Anasayfa scroll controller'ı resetle
            } else {
              setState(() => _currentIndex = 0);
            }
          },
          child: Text(
            'Kabook',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.primary,
              letterSpacing: -0.5,
            ),
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            // Bildirim rozetini (kırmızı nokta) buraya taşıdık
            icon: const NotificationBadge(child: Icon(Icons.notifications_outlined)),
            onPressed: () {
              // Sekme değiştirmek yerine sayfayı açıyoruz
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const NotificationsPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.mail_outline),
            onPressed: () => context.push('/messages'),
          ),
          const SizedBox(width: 8),
        ],
      ),

      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),

      floatingActionButton: _buildFloatingActionButton(context),

      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onItemTapped,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Anasayfa',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_outlined),
            selectedIcon: Icon(Icons.event),
            label: 'Etkinlikler',
          ),
          // 🎬 REELS İKONU (ORTA)
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library),
            label: 'Reels',
          ),
          NavigationDestination(
            icon: Icon(Icons.support_agent_outlined),
            selectedIcon: Icon(Icons.support_agent),
            label: 'Yardım',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }

  Widget? _buildFloatingActionButton(BuildContext context) {
    final theme = Theme.of(context);

    if (_currentIndex == 0) {
      return FloatingActionButton(
        onPressed: () => context.push('/create-post'),
        backgroundColor: theme.colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      );
    }

    if (_currentIndex == 1) { // Etkinlikler artık index 1
      return FloatingActionButton(
        onPressed: () => context.push('/create-event'),
        backgroundColor: theme.colorScheme.secondary,
        child: const Icon(Icons.add, color: Colors.white),
      );
    }

    return null;
  }
}
