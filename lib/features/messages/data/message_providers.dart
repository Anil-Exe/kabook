import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import '../../../services/appwrite_service.dart';
import '../../../core/config/appwrite_config.dart';
import '../../auth/data/auth_providers.dart';
import 'message_service.dart';
import '../../follow/data/follow_service.dart';
import '../../block/data/block_service.dart';
import '../../notifications/data/notification_service.dart';

/// MessageService Provider
final messageServiceProvider = Provider<MessageService>((ref) {
  return MessageService(
    databases: AppwriteService.databases,
    realtime: AppwriteService.realtime,
    followService: ref.read(followServiceProvider),
    blockService: ref.read(blockServiceProvider),
    notificationService: ref.read(notificationServiceProvider),
  );
});

/// 💬 Ana Sohbet Listesi (Sadece 'active' olanlar)
final myChatsProvider = FutureProvider.autoDispose<List<models.Document>>((ref) async {
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return [];
  
  final service = ref.read(messageServiceProvider);
  
  // 🔥 DÜZELTME: Tüm sohbetleri çekip hafızada filtreliyoruz.
  // Böylece 'request' durumunda olsa bile BENİM başlattığım sohbetleri görebilirim.
  final allChats = await service.getUserChats(user.$id, status: null);

  return allChats.where((doc) {
    // Ekstra Güvenlik: Kullanıcı katılımcı mı?
    final List<dynamic> participants = doc.data['participantIds'] ?? [];
    if (!participants.contains(user.$id)) return false;

    final status = doc.data['status'];
    final initiatedBy = doc.data['initiatedBy'];
    
    // Aktif sohbetler VEYA benim başlattığım istekler görünsün
    if (status == 'active') return true;
    if (status == 'request' && initiatedBy == user.$id) return true;
    
    return false;
  }).toList();
});

/// 📩 Mesaj İstekleri Listesi (Sadece 'request' olanlar ve bana gelenler)
final messageRequestsProvider = FutureProvider.autoDispose<List<models.Document>>((ref) async {
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return [];
  
  final service = ref.read(messageServiceProvider);
  
  // 'request' statüsündeki sohbetleri getir
  final requests = await service.getUserChats(user.$id, status: 'request');

  // Sadece BAŞKASININ başlattığı (bana gelen) istekleri filtrele
  // Eğer ben başlattıysam (initiatedBy == me), bu benim gönderdiğim istektir, gelen kutumda durmasın.
  return requests.where((doc) => doc.data['initiatedBy'] != user.$id).toList();
});

/// 💬 Seçili Sohbetin Mesajları
final chatMessagesProvider = FutureProvider.family.autoDispose<List<models.Document>, String>((ref, chatId) async {
  final service = ref.watch(messageServiceProvider);
  return service.getMessages(chatId: chatId);
});

///  Realtime Mesaj Dinleyici (Chat ID'ye göre)
final chatRealtimeProvider = StreamProvider.family.autoDispose<RealtimeMessage, String>((ref, chatId) {
  final service = ref.read(messageServiceProvider);
  return service.subscribeToChatMessages(chatId);
});

/// 🔔 Realtime Sohbet Listesi Dinleyici
final myChatsRealtimeProvider = StreamProvider.autoDispose<RealtimeMessage>((ref) {
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return const Stream.empty();
  
  final service = ref.read(messageServiceProvider);
  return service.subscribeToUserChats(user.$id);
});