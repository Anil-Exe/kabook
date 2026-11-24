import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/appwrite_config.dart';
import '../../../services/appwrite_service.dart';
import '../../auth/data/auth_providers.dart';
import 'notification_model.dart';
import 'notification_service.dart';

/// 🔔 Bildirim Listesi Provider'ı (Realtime)
final notificationsProvider = StreamProvider.autoDispose<List<NotificationModel>>((ref) {
  final currentUser = ref.watch(currentUserProvider).value;
  if (currentUser == null) return const Stream.empty();

  final controller = StreamController<List<NotificationModel>>();
  final service = ref.read(notificationServiceProvider);

  // 1. İlk Yükleme
  Future<void> load() async {
    try {
      final notifications = await service.getUserNotifications(currentUser.$id);
      if (!controller.isClosed) controller.add(notifications);
    } catch (e) {
      if (!controller.isClosed) controller.addError(e);
    }
  }

  load();

  // 2. Realtime Aboneliği
  final realtime = AppwriteService.realtime;
  final subscription = realtime.subscribe([
    'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.notificationsCollectionId}.documents'
  ]);

  subscription.stream.listen((event) {
    // Yeni bildirim geldiğinde veya okundu olduğunda listeyi yenile
    // (Daha optimize yapılabilir ama şimdilik güvenli olan bu)
    if (event.payload.isNotEmpty) {
      final data = event.payload;
      // Sadece bana gelen bildirimler veya benim okuduğum bildirimler için yenile
      if (data['toUserId'] == currentUser.$id) {
        load();
      }
    }
  });

  ref.onDispose(() {
    subscription.close();
    controller.close();
  });

  return controller.stream;
});

/// 🔴 Okunmamış Bildirim Sayısı Provider'ı (Badge için)
final unreadNotificationCountProvider = StateNotifierProvider<UnreadCountNotifier, int>((ref) {
  return UnreadCountNotifier(ref);
});

class UnreadCountNotifier extends StateNotifier<int> {
  final Ref ref;
  StreamSubscription? _subscription;

  UnreadCountNotifier(this.ref) : super(0) {
    _init();
  }

  Future<void> _init() async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;

    // İlk sayıyı çek
    await refreshCount();

    // Realtime dinle
    final realtime = AppwriteService.realtime;
    _subscription = realtime.subscribe([
      'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.notificationsCollectionId}.documents'
    ]).stream.listen((event) {
      final data = event.payload;
      
      // Bana gelen bir bildirimse
      if (data['toUserId'] == user.$id) {
        // Yeni oluşturulduysa (create) -> Artır
        if (event.events.any((e) => e.endsWith('.create'))) {
          state++;
        }
        // Güncellendiyse (update) -> Tekrar say (okundu yapılmış olabilir)
        else if (event.events.any((e) => e.endsWith('.update'))) {
          refreshCount();
        }
      }
    });
  }

  Future<void> refreshCount() async {
    final user = ref.read(currentUserProvider).value;
    if (user != null) {
      final count = await ref.read(notificationServiceProvider).getUnreadCount(user.$id);
      state = count;
    }
  }

  /// Manuel olarak okundu işaretlendiğinde UI'ı güncellemek için
  void decrement() {
    if (state > 0) state--;
  }

  /// Belirli bir bildirimi okundu yap
  Future<void> markAsRead(String notificationId) async {
    await ref.read(notificationServiceProvider).markAsRead(notificationId);
    // Realtime zaten dinliyor ama anlık tepki için:
    refreshCount(); 
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
