import 'dart:io';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/appwrite_config.dart';
import '../../../services/appwrite_service.dart';
import '../../notifications/data/notification_service.dart';

final storyServiceProvider = Provider((ref) => StoryService(ref.read(notificationServiceProvider)));

class StoryService {
  final Databases _databases = AppwriteService.databases;
  final Storage _storage = Storage(AppwriteService.client);
  final NotificationService _notificationService;

  StoryService(this._notificationService);

  /// 📸 Hikaye Paylaş
  Future<void> createStory({
    required String userId,
    required File mediaFile,
    required String mediaType, // 'image' or 'video'
    int duration = 5,
    String? caption,
    String? location,
    String? musicUrl,
    String? musicTitle,
  }) async {
    try {
      // 1. Medyayı Yükle
      final file = await _storage.createFile(
        bucketId: AppwriteConfig.storageBucketId,
        fileId: ID.unique(),
        file: InputFile.fromPath(path: mediaFile.path),
      );

      // 2. Bitiş Süresini Hesapla (24 Saat)
      final expiresAt = DateTime.now().add(const Duration(hours: 24));

      // 3. Veritabanına Kaydet
      await _databases.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.storiesCollectionId,
        documentId: ID.unique(),
        data: {
          'userId': userId,
          'mediaUrl': file.$id, // Storage ID'sini tutuyoruz
          'mediaType': mediaType,
          'duration': duration,
          'caption': caption,
          'location': location,
          'viewers': <String>[], // Tip güvenliği için String liste
          'likedBy': <String>[], // Tip güvenliği için String liste
          'expirestAt': expiresAt.toIso8601String(),
          'musicUrl': musicUrl,
          'musicTitle': musicTitle,
        },
      );
    } catch (e) {
      throw Exception('Hikaye paylaşılamadı: $e');
    }
  }

  /// 📥 Takip Edilenlerin Hikayelerini Getir
  Future<List<models.Document>> getStoriesFeed(List<String> followingIds) async {
    if (followingIds.isEmpty) return [];

    try {
      final now = DateTime.now().toIso8601String();

      // Takip edilenlerin ve süresi dolmamış hikayeleri getir
      final result = await _databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.storiesCollectionId,
        queries: [
          Query.equal('userId', followingIds),
          Query.greaterThan('expirestAt', now), // Süresi dolmamışlar
          Query.orderAsc('\$createdAt'), // Eskiden yeniye doğru (Kronolojik)
        ],
      );
      return result.documents;
    } catch (e) {
      print('Hikayeler yüklenemedi: $e');
      return [];
    }
  }

  /// 👤 Kendi Hikayelerim
  Future<List<models.Document>> getMyStories(String userId) async {
    final now = DateTime.now().toIso8601String();
    final result = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.storiesCollectionId,
      queries: [
        Query.equal('userId', userId),
        Query.greaterThan('expirestAt', now),
        Query.orderAsc('\$createdAt'), // Eskiden yeniye doğru
      ],
    );
    return result.documents;
  }

  /// 👀 Hikayeyi Görüntüle (View Ekle)
  Future<void> viewStory(String storyId, String userId, String ownerId) async {
    // Kullanıcı kendi hikayesini izliyorsa izlenme sayma
    if (userId == ownerId) return;

    try {
      final doc = await _databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.storiesCollectionId,
        documentId: storyId,
      );

      List<dynamic> viewers = doc.data['viewers'] ?? [];
      
      if (!viewers.contains(userId)) {
        viewers.add(userId);
        await _databases.updateDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.storiesCollectionId,
          documentId: storyId,
          data: {'viewers': viewers},
        );
      }
    } catch (e) {
      print('View eklenemedi: $e');
    }
  }

  /// ❤️ Hikayeyi Beğen / Beğenmekten Vazgeç
  Future<void> toggleLikeStory(String storyId, String userId) async {
    try {
      // DB'den en güncel durumu çekiyoruz (Race condition ve çift tetiklemeyi önlemek için)
      final doc = await _databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.storiesCollectionId,
        documentId: storyId,
      );

      List<String> updatedLikes = List<String>.from(doc.data['likedBy'] ?? []);
      final ownerId = doc.data['userId'];
      bool isAdded = false;
      
      if (updatedLikes.contains(userId)) {
        updatedLikes.remove(userId);
      } else {
        updatedLikes.add(userId);
        isAdded = true;
      }

      await _databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.storiesCollectionId,
        documentId: storyId,
        data: {'likedBy': updatedLikes},
      );
      
      // Kendi hikayesini beğenmediyse ve yeni eklendiyse bildirim at
      if (isAdded && ownerId != userId) {
        await _notificationService.createNotification(
          toUserId: ownerId,
          fromUserId: userId,
          type: 'story_like',
          content: 'Hikayeni beğendi',
          eventId: userId, // Yönlendirme için beğenenin profil ID'si
        );
      }

    } catch (e) {
      print('Beğeni işlemi başarısız: $e');
      // Hata durumunda UI'ı geri almak için exception fırlatılabilir
      // throw e; 
    }
  }

  /// 🔍 Medya ID'sinden Hikayeyi Bul (Chat Reply için)
  Future<models.Document?> getStoryByMediaId(String mediaId) async {
    try {
      final result = await _databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.storiesCollectionId,
        queries: [
          Query.equal('mediaUrl', mediaId),
          Query.limit(1),
        ],
      );
      return result.documents.isNotEmpty ? result.documents.first : null;
    } catch (_) {
      return null;
    }
  }

  /// 🗑️ Hikaye Sil
  Future<void> deleteStory(String storyId, String mediaId) async {
    try {
      // Önce görseli sil
      await _storage.deleteFile(
        bucketId: AppwriteConfig.storageBucketId,
        fileId: mediaId,
      );
    } catch (_) {}

    await _databases.deleteDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.storiesCollectionId,
      documentId: storyId,
    );
  }
}
