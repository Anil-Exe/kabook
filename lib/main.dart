import 'package:flutter/material.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart'; // 1. Import Ekle
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'features/profile/data/theme_provider.dart';
import 'services/push_notification_service.dart'; // Yeni servis importu

void main() async { // 2. async yap
  WidgetsFlutterBinding.ensureInitialized(); // 3. Binding başlat
  await initializeDateFormatting('tr_TR', null); // 4. Tarih formatını yükle
  await Firebase.initializeApp(); // Firebase başlat
  
  final prefs = await SharedPreferences.getInstance();

  runApp(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
    child: const MyApp(),
  ));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    _setupFirebaseMessaging();
  }

  Future<void> _setupFirebaseMessaging() async {
    // 1. Token Kaydı ve İzinler (Yeni Servis Üzerinden)
    // ProviderContainer olmadığı için manuel çağırıyoruz veya ref.read kullanıyoruz (initState içinde ref.read güvenli olmayabilir, afterLayout daha iyi ama şimdilik basit tutalım)
    // En temizi AuthService yerine oluşturduğumuz servisi kullanmak.
    final pushService = PushNotificationService();
    await pushService.registerDeviceToken();

    // 2. Uygulama Kapalıyken Gelen Bildirime Tıklama (Terminated)
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        _handleNotificationTap(message);
      }
    });

    // 3. Uygulama Arka Plandayken Gelen Bildirime Tıklama (Background)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // 🆕 EKLENDİ: Uygulama Açıkken Gelen Bildirim (Foreground)
    // Bunu eklemezsen uygulama açıkken bildirim geldiğini göremezsin.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('🔔 Ön Planda Bildirim Geldi: ${message.notification?.title}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🔔 ${message.notification?.title ?? "Bildirim"}: ${message.notification?.body ?? ""}'),
            backgroundColor: Colors.blueAccent,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });
  }

  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    
    // FCM'den gelen payload'da farklı ID anahtarları olabilir
    final String? id = data['id'] ?? data['chatId'] ?? data['eventId'];
    final String? type = data['type'];
    final String? fromUserId = data['fromUserId'] ?? data['senderId'];
    
    final targetId = id ?? fromUserId;

    if (targetId != null) {
      // Router hazır olduğunda yönlendir (Hafif gecikme güvenli olur, ama 1000ms çok uzundu)
      Future.delayed(const Duration(milliseconds: 500), () {
        final router = ref.read(appRouterProvider);
        try {
          switch (type) {
            case 'message':
              router.push('/chat/$targetId', extra: data['senderName'] ?? 'Sohbet'); // chatId
              break;
            case 'like':
            case 'post_like':
            case 'comment':
            case 'comment_reply':
            case 'repost':
            case 'mention':
              router.push('/post/$targetId'); // postId
              break;
            case 'follow':
            case 'story_like':
            case 'friend_request':
            case 'friend_accepted':
              router.push('/profile/$targetId'); // userId
              break;
            case 'event':
            case 'event_application':
            case 'event_approved':
            case 'event_rejected':
              router.push('/event/$targetId'); // eventId
              break;
            default:
              router.push('/notifications');
          }
        } catch (e) {
          debugPrint('Yönlendirme hatası: $e');
        }
      });
    } else {
      // Payload eksikse genel bildirim sayfasına at
      Future.delayed(const Duration(milliseconds: 500), () {
        ref.read(appRouterProvider).push('/notifications');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'KaBOOK',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
