import 'dart:io';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/appwrite_config.dart';
import 'appwrite_service.dart';
import '../features/notifications/data/notification_service.dart';

final eventServiceProvider = Provider<EventService>((ref) {
  final notificationService = ref.watch(notificationServiceProvider);
  return EventService(notificationService);
});

class EventService {
  final Databases _databases = AppwriteService.databases;
  final Storage _storage = Storage(AppwriteService.client);
  final NotificationService _notificationService;

  EventService(this._notificationService);

  /// Etkinlik görselini yükle
  Future<String> uploadEventImage(File imageFile) async {
    try {
      final inputFile = InputFile.fromPath(path: imageFile.path, filename: imageFile.path.split(Platform.pathSeparator).last);
      final file = await _storage.createFile(
        bucketId: AppwriteConfig.storageBucketId,
        fileId: ID.unique(),
        file: inputFile,
      );
      return file.$id;
    } catch (e) {
      throw Exception('Görsel yüklenemedi: $e');
    }
  }

  Future<models.Document> createEvent({
    required String title,
    required String description,
    required String location,
    required DateTime eventDate,
    required String creatorId,
    String? imageId,
    int maxParticipants = 50,
    String category = 'Diğer',
  }) async {
    try {
      return await _databases.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventsCollectionId,
        documentId: ID.unique(),
        data: {
          'title': title,
          'description': description,
          'location': location,
          'eventDate': eventDate.toIso8601String(), // Appwrite için ISO formatı şart
          'creatorId': creatorId,
          'imageId': imageId,
          'likesCount': 0,
          'maxParticipants': maxParticipants,
          'participantsCount': 0,
          'isActive': true,
          'category': category,
        },
      );
    } catch (e) {
      throw Exception('Etkinlik oluşturulamadı: $e');
    }
  }

  /// 📩 Etkinliğe katılma isteği gönder (+ Bildirim)
  Future<void> sendJoinRequest({
    required String eventId,
    required String userId,
    required String creatorId,
    required String senderName,
  }) async {
    if (userId.isEmpty || creatorId.isEmpty) {
      throw Exception('Hata: Kullanıcı ID veya Etkinlik Sahibi ID boş.');
    }

    try {
      // 1. İstek tablosuna 'pending' olarak ekle (event_join_requests)
      await _databases.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventJoinRequestsCollectionId,
        documentId: ID.unique(),
        data: {
          'eventId': eventId,
          'userId': userId,
          'creatorId': creatorId, // Veri bütünlüğü için eklendi
          'status': 'pending', // Başlangıçta beklemede
        },
        // Kod tarafındaki izinleri kaldırıyoruz.
        // İzinleri Appwrite Console -> Database -> event_join_requests -> Settings -> Permissions kısmından "Any" veya "Users" olarak ayarlayın.
      );

      // 2. Etkinlik sahibine bildirim gönder
      try {
        await _notificationService.createNotification(
          toUserId: creatorId,
          fromUserId: userId,
          type: 'event_join_request',
          content: '$senderName, etkinliğine katılmak istiyor.',
          eventId: eventId,
        );
      } catch (e) {
        print('Bildirim oluşturulamadı (Önemsiz): $e');
        // Bildirim hatası ana işlemi bozmasın diye yutuyoruz
      }
    } on AppwriteException catch (e) {
      throw Exception('Etkinliğe katılma isteği gönderilemedi: ${e.message}');
    } catch (e) {
      throw Exception('Etkinliğe katılma isteği gönderilemedi: $e');
    }
  }

  /// Kullanıcının katılım durumunu getir (pending, accepted, rejected veya null)
  Future<String?> getUserJoinStatus(String eventId, String userId) async {
    try {
      // 1. Önce katılımcı listesinde var mı diye bak (Zaten katılmış mı?)
      final participantCheck = await _databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventParticipantsCollectionId,
        queries: [
          Query.equal('eventId', eventId),
          Query.equal('userId', userId),
          Query.limit(1),
        ],
      );

      if (participantCheck.documents.isNotEmpty) {
        return 'approved'; // Zaten katılımcı
      }
      
      // 2. Yoksa, isteklerde durumu ne?
      final requestCheck = await _databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventJoinRequestsCollectionId,
        queries: [
          Query.equal('eventId', eventId),
          Query.equal('userId', userId),
          Query.limit(1),
        ],
      );

      if (requestCheck.documents.isNotEmpty) {
        return requestCheck.documents.first.data['status'];
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Bekleyen katılım isteklerini getir (Etkinlik sahibi için)
  Future<List<models.Document>> getPendingRequests(String eventId) async {
    try {
      final result = await _databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventJoinRequestsCollectionId,
        queries: [
          Query.equal('eventId', eventId),
          Query.equal('status', 'pending'),
        ],
      );
      return result.documents;
    } catch (e) {
      return [];
    }
  }

  /// ✅ İsteği Onayla (Wrapper)
  Future<void> approveJoinRequest({required String requestId, required String eventId, required String userId}) async {
    try {
      // 1. İsteği 'approved' yap
      await _databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventJoinRequestsCollectionId,
        documentId: requestId,
        data: {'status': 'approved'},
      );

      // 2. Kullanıcıyı 'event_participants' tablosuna ekle
      await _databases.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventParticipantsCollectionId,
        documentId: ID.unique(),
        data: {
          'eventId': eventId,
          'userId': userId,
          'joinedAt': DateTime.now().toIso8601String(),
          'status': 'accepted', // ✅ EKLENDİ: Zorunlu alan hatasını çözer
        },
        // İzinler Appwrite Panelinden yönetilecek
      );

      // 3. Etkinlik katılımcı sayısını artır
      final eventDoc = await _databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventsCollectionId,
        documentId: eventId,
      );
      final currentCount = eventDoc.data['participantsCount'] ?? 0;
      final int newCount = (currentCount is int) ? currentCount + 1 : 1;

      await _databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventsCollectionId,
        documentId: eventId,
        data: {'participantsCount': newCount},
      );

      // 4. Kullanıcıya bildirim gönder
      await _notificationService.createNotification(
        toUserId: userId,
        fromUserId: eventDoc.data['creatorId'],
        type: 'event_join_approved',
        content: 'Etkinlik katılım isteğin onaylandı!',
        eventId: eventId,
      );

    } catch (e) {
      throw Exception('Onaylama işlemi başarısız: $e');
    }
  }

  /// ❌ İsteği Reddet (Wrapper)
  Future<void> rejectJoinRequest({required String requestId, required String eventId, required String userId}) async {
    try {
      await _databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventJoinRequestsCollectionId,
        documentId: requestId,
        data: {'status': 'rejected'},
      );

      // Etkinlik sahibini bulmak için event dokümanını çekelim
      final eventDoc = await _databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventsCollectionId,
        documentId: eventId,
      );

      // Reddedildi bildirimi gönder
      await _notificationService.createNotification(
        toUserId: userId,
        fromUserId: eventDoc.data['creatorId'],
        type: 'event_join_rejected',
        content: 'Etkinlik katılım isteğin reddedildi.',
        eventId: eventId,
      );
    } catch (e) {
      throw Exception('Reddetme işlemi başarısız: $e');
    }
  }

  /// 🚫 Katılım İsteğini İptal Et (Kullanıcı)
  Future<void> cancelJoinRequest({required String eventId, required String userId}) async {
    try {
      final result = await _databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventJoinRequestsCollectionId,
        queries: [
          Query.equal('eventId', eventId),
          Query.equal('userId', userId),
          Query.equal('status', 'pending'),
        ],
      );

      if (result.documents.isNotEmpty) {
        await _databases.deleteDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.eventJoinRequestsCollectionId,
          documentId: result.documents.first.$id,
        );
      }
    } catch (e) {
      throw Exception('İstek iptal edilemedi: $e');
    }
  }

  /// 🗑️ Katılımcıyı Çıkar (Etkinlik Sahibi)
  Future<void> removeParticipant({required String eventId, required String userId}) async {
    try {
      // 1. Katılımcı kaydını bul
      final result = await _databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventParticipantsCollectionId,
        queries: [
          Query.equal('eventId', eventId),
          Query.equal('userId', userId),
        ],
      );

      if (result.documents.isNotEmpty) {
        // 2. Kaydı sil
        await _databases.deleteDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.eventParticipantsCollectionId,
          documentId: result.documents.first.$id,
        );

        // 2.1. İlgili katılım isteğini de sil (event_join_requests)
        // Bu işlem yapılmazsa, kullanıcı çıkarılsa bile "Katılıyorsun" görmeye devam eder.
        final requests = await _databases.listDocuments(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.eventJoinRequestsCollectionId,
          queries: [
            Query.equal('eventId', eventId),
            Query.equal('userId', userId),
          ],
        );
        
        for (var req in requests.documents) {
          await _databases.deleteDocument(
            databaseId: AppwriteConfig.databaseId,
            collectionId: AppwriteConfig.eventJoinRequestsCollectionId,
            documentId: req.$id,
          );
        }

        // 3. Katılımcı sayısını güncelle
        final eventDoc = await _databases.getDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.eventsCollectionId,
          documentId: eventId,
        );
        final currentCount = eventDoc.data['participantsCount'] ?? 0;
        final int newCount = (currentCount is int && currentCount > 0) ? currentCount - 1 : 0;

        await _databases.updateDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.eventsCollectionId,
          documentId: eventId,
          data: {'participantsCount': newCount},
        );
      }
    } catch (e) {
      throw Exception('Katılımcı çıkarılamadı: $e');
    }
  }

  /// Beğeni durumunu kontrol et
  Future<bool> isEventLiked(String eventId, String userId) async {
    try {
      final result = await _databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventLikesCollectionId,
        queries: [
          Query.equal('relatedId', eventId),
          Query.equal('userId', userId),
          Query.equal('type', 'like'),
          Query.limit(1),
        ],
      );
      return result.documents.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Beğeni durumunu değiştir (Like/Unlike)
  Future<void> toggleLike(String eventId, String userId) async {
    try {
      final result = await _databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventLikesCollectionId,
        queries: [
          Query.equal('relatedId', eventId),
          Query.equal('userId', userId),
          Query.equal('type', 'like'),
          Query.limit(1),
        ],
      );

      if (result.documents.isNotEmpty) {
        // Zaten beğenilmiş -> Sil (Unlike)
        await _databases.deleteDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.eventLikesCollectionId,
          documentId: result.documents.first.$id,
        );
        await _updateLikeCount(eventId, -1);
      } else {
        // Beğenilmemiş -> Ekle (Like)
        await _databases.createDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.eventLikesCollectionId,
          documentId: ID.unique(),
          data: {
            'userId': userId,
            'relatedId': eventId,
            'type': 'like',
            'createdAt': DateTime.now().toIso8601String(),
          },
        );
        await _updateLikeCount(eventId, 1);
      }
    } catch (e) {
      throw Exception('Beğeni işlemi başarısız: $e');
    }
  }

  Future<void> _updateLikeCount(String eventId, int change) async {
    try {
      final eventDoc = await _databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventsCollectionId,
        documentId: eventId,
      );
      final currentLikes = eventDoc.data['likesCount'] ?? 0;
      await _databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventsCollectionId,
        documentId: eventId,
        data: {'likesCount': currentLikes + change},
      );
    } catch (_) {}
  }
}