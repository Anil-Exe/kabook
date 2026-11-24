import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/data/auth_providers.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/messages/presentation/pages/messages_page.dart';
import '../../features/messages/presentation/pages/chat_page.dart';
import '../../features/messages/presentation/pages/group_info_page.dart';
import '../../features/messages/presentation/pages/chat_info_page.dart';
import '../../features/messages/presentation/pages/chat_media_page.dart';
import '../../features/messages/presentation/pages/new_chat_page.dart';
import '../../features/profile/presentation/pages/settings_page.dart';
import '../../features/profile/presentation/pages/edit_profile_page.dart';
import '../../features/post/presentation/pages/create_post_page.dart';
import '../../features/post/presentation/pages/post_details_page.dart';
import '../pages/splash_page.dart';
import '../pages/help_page.dart';
import '../pages/qr_page.dart';
import '../layout/search_page.dart';
import '../../features/events/presentation/pages/events_page.dart';
import '../../features/events/presentation/pages/event_details_page.dart';
import '../../features/events/presentation/pages/create_event_page.dart';
import '../../features/events/presentation/pages/edit_event_page.dart';
import '../layout/main_layout.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final isLoggedIn = ref.watch(isLoggedInProvider);

  return GoRouter(
    debugLogDiagnostics: true,
    initialLocation: '/splash',
    redirect: (context, state) {
      final isAuthenticated = isLoggedIn.value ?? false;
      final isGoingToAuth = state.matchedLocation == '/login' || state.matchedLocation == '/register';

      // Giriş yapılmamışsa ve auth sayfalarında değilse login'e yönlendir
      if (!isAuthenticated && !isGoingToAuth && state.matchedLocation != '/splash') {
        return '/login';
      }

      // Giriş yapılmışsa ve auth sayfalarındaysa ana sayfaya yönlendir
      if (isAuthenticated && isGoingToAuth) {
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) => const MainLayout(),
      ),
      GoRoute(
        path: '/profile/:userId',
        name: 'profile',
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;
          return ProfilePage(userId: userId);
        },
      ),
      GoRoute(
        path: '/notifications',
        name: 'notifications',
        builder: (context, state) => const NotificationsPage(),
      ),
      GoRoute(
        path: '/messages',
        name: 'messages',
        builder: (context, state) => const MessagesPage(),
      ),
      GoRoute(
        path: '/new-chat',
        name: 'new-chat',
        builder: (context, state) => const NewChatPage(),
      ),
      GoRoute(
        path: '/chat/:chatId',
        name: 'chat',
        builder: (context, state) {
          final chatId = state.pathParameters['chatId']!;
          final title = state.extra as String? ?? 'Sohbet';
          return ChatPage(chatId: chatId, chatTitle: title);
        },
      ),
      GoRoute(
        path: '/group-info/:chatId',
        name: 'group-info',
        builder: (context, state) {
          final chatId = state.pathParameters['chatId']!;
          return GroupInfoPage(chatId: chatId);
        },
      ),
      GoRoute(
        path: '/chat-info/:chatId/:otherUserId',
        name: 'chat-info',
        builder: (context, state) {
          final chatId = state.pathParameters['chatId']!;
          final otherUserId = state.pathParameters['otherUserId']!;
          return ChatInfoPage(chatId: chatId, otherUserId: otherUserId);
        },
      ),
      GoRoute(
        path: '/chat-media/:chatId',
        name: 'chat-media',
        builder: (context, state) {
          final chatId = state.pathParameters['chatId']!;
          return ChatMediaPage(chatId: chatId);
        },
      ),
      GoRoute(
        path: '/help',
        name: 'help',
        builder: (context, state) => const HelpPage(),
      ),
      GoRoute(
        path: '/qr',
        name: 'qr',
        builder: (context, state) => const QRPage(),
      ),
      GoRoute(
        path: '/search',
        name: 'search',
        builder: (context, state) => const SearchPage(),
      ),
      GoRoute(
        path: '/events',
        name: 'events',
        builder: (context, state) => const EventsPage(),
      ),
      GoRoute(
        path: '/create-event',
        name: 'create-event',
        builder: (context, state) => const CreateEventPage(),
      ),
      GoRoute(
        path: '/event/:eventId',
        name: 'event-details',
        builder: (context, state) {
          final eventId = state.pathParameters['eventId']!;
          return EventDetailsPage(eventId: eventId);
        },
      ),
      GoRoute(
        path: '/event/:eventId/edit',
        name: 'edit-event',
        builder: (context, state) {
          final eventId = state.pathParameters['eventId']!;
          return EditEventPage(eventId: eventId);
        },
      ),
      GoRoute(
        path: '/post/:postId',
        name: 'post-details',
        builder: (context, state) {
          final postId = state.pathParameters['postId'] ?? '';
          return PostDetailsPage(postId: postId);
        },
      ),
      // 🆕 EKLENEN ROTALAR
      GoRoute(
        path: '/create-post',
        name: 'create-post',
        builder: (context, state) => const CreatePostPage(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/edit-profile',
        name: 'edit-profile',
        builder: (context, state) => const EditProfilePage(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Hata')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('Sayfa bulunamadı:\n${state.uri}', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go('/home'),
              child: const Text('Ana Sayfaya Dön'),
            ),
          ],
        ),
      ),
    ),
  );
});
