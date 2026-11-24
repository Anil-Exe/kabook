import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/appwrite_config.dart';
import '../../../services/appwrite_service.dart';
import 'notification_model.dart';

final notificationServiceProvider = Provider((ref) => NotificationService());

class NotificationService {
  final Databases _databases = AppwriteService.databases;

  /// 🔔 Bildirim Oluştur
  Future<void> createNotification({
    required String toUserId,
    required String fromUserId,
    required String type,
    required String content,
    required String eventId,
    String status = 'unread',
    bool isRead = false,
  }) async {
    // 🔍 DEBUG LOGLARI
    print('🔥 createNotification ÇAĞRILDI');
    print('receiverUserId: $toUserId');
    print('senderUserId: $fromUserId');
    print('type: $type');

    // Kullanıcı kendine bildirim atmasın
    if (toUserId == fromUserId) {
      print('⚠️ createNotification İPTAL: toUserId == fromUserId');
      return;
    }

    try {
      await _databases.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.notificationsCollectionId,
        documentId: ID.unique(),
        data: {
          'toUserId': toUserId,
          'fromUserId': fromUserId,
          'type': type,
          'eventId': eventId,
          'status': status,
          'content': content,
          'isRead': isRead,
        },
      );
      print('✅ createNotification BAŞARILI');
    } catch (e) {
      // Bildirim hatası akışı bozmamalı, sadece logla
      print('❌ createNotification HATASI: $e');
    }
  }

  /// 📥 Kullanıcının Bildirimlerini Getir
  Future<List<NotificationModel>> getUserNotifications(String userId) async {
    try {
      // 1. Normal Bildirimleri Çek
      final notificationsResult = await _databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.notificationsCollectionId,
        queries: [
          Query.equal('toUserId', userId),
          Query.orderDesc('\$createdAt'),
        ],
      );

      final notifications = notificationsResult.documents
          .map(NotificationModel.fromDocument)
          .toList();

      // 2. Takip İsteklerini Çek (Yedekleme/Garanti)
      // Bildirim oluşmamış olsa bile follows tablosundan bekleyenleri alıyoruz
      final followRequestsResult = await _databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.followsCollectionId,
        queries: [
          Query.equal('followingId', userId),
          Query.equal('status', 'pending'),
        ],
      );

      // Takip isteklerini NotificationModel'e dönüştür
      for (var doc in followRequestsResult.documents) {
        // Eğer bu istek için zaten bir bildirim varsa tekrar ekleme (eventId = followerId varsayımıyla)
        final alreadyExists = notifications.any((n) => 
            n.type == 'follow_request' && n.fromUserId == doc.data['followerId']);
        
        if (!alreadyExists) {
          notifications.add(_createMockNotificationFromFollow(doc));
        }
      }

      // Tarihe göre yeniden sırala (En yeni en üstte)
      notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return notifications;
    } catch (e) {
      throw Exception('Bildirimler yüklenemedi: $e');
    }
  }

  /// 🔴 Okunmamış Bildirim Sayısını Getir
  Future<int> getUnreadCount(String userId) async {
    final result = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.notificationsCollectionId,
      queries: [
        Query.equal('toUserId', userId),
        Query.equal('isRead', false),
        Query.limit(1), // Sadece toplam sayıyı almak için limit 1 yeterli (total döner)
      ],
    );
    return result.total;
  }

  /// Follows dokümanını geçici bir NotificationModel'e çevirir
  NotificationModel _createMockNotificationFromFollow(Document doc) {
    return NotificationModel(
      id: doc.$id,
      toUserId: doc.data['followingId'],
      fromUserId: doc.data['followerId'],
      type: 'follow_request',
      eventId: doc.data['followerId'], // Profil için ID
      status: 'unread',
      content: 'Seni takip etmek istiyor', // İsim sonradan UI'da çekilebilir
      isRead: false,
      createdAt: DateTime.parse(doc.$createdAt),
    );
  }

  /// 👀 Okundu Olarak İşaretle
  Future<void> markAsRead(String notificationId) async {
    await _databases.updateDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.notificationsCollectionId,
      documentId: notificationId,
      data: {'isRead': true},
    );
  }

  /// ✅ Tümünü Okundu İşaretle (Client-side loop for now)
  Future<void> markAllAsRead(List<String> notificationIds) async {
    // Not: İdealde bu bir Appwrite Function olmalı, ama şimdilik döngü ile:
    for (var id in notificationIds) {
      // Hata yönetimi her biri için ayrı yapılabilir veya toplu beklenebilir
      _databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.notificationsCollectionId,
        documentId: id,
        data: {'isRead': true},
      ).catchError((_) {}); // Hata olursa yut, UI zaten güncellenecek
    }
  }

  /// 🗑️ Bildirim Sil
  Future<void> deleteNotification(String notificationId) async {
    await _databases.deleteDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.notificationsCollectionId,
      documentId: notificationId,
    );
  }
}