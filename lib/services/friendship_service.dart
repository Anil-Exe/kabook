import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/appwrite_config.dart';
import 'appwrite_service.dart';
import '../features/notifications/data/notification_service.dart';

final friendshipServiceProvider = Provider((ref) => FriendshipService(AppwriteService.client, ref.watch(notificationServiceProvider)));

class FriendshipService {
  final Databases _databases;
  final NotificationService _notificationService;
  // Appwrite'da 'friendships' ID'li bir koleksiyon oluşturduğunuzdan emin olun
  static const String friendshipsCollectionId = 'follows'; 

  FriendshipService(Client client, this._notificationService) : _databases = Databases(client);

  /// Arkadaşlık isteği gönder
  Future<void> sendFriendRequest(String currentUserId, String targetUserId) async {
    // Mevcut ilişkiyi kontrol et
    final existing = await checkFriendshipStatus(currentUserId, targetUserId);
    if (existing != null) {
      throw Exception('Zaten bir arkadaşlık kaydı mevcut.');
    }

    await _databases.createDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: friendshipsCollectionId,
      documentId: ID.unique(),
      data: {
        'followerId': currentUserId,
        'followingId': targetUserId,
        'status': 'pending',
      },
    );

    // 🔔 Bildirim Gönder
    try {
      // Gönderenin adını al
      String senderName = 'Bir kullanıcı';
      try {
        final senderDoc = await _databases.getDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.usersCollectionId,
          documentId: currentUserId,
        );
        senderName = senderDoc.data['displayName'] ?? senderName;
      } catch (_) {}

      await _databases.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.notificationsCollectionId,
        documentId: ID.unique(),
        data: {
          'toUserId': targetUserId,
          'fromUserId': currentUserId,
          'content': '$senderName seni arkadaş olarak ekledi',
          'type': 'friend_request',
          'eventId': currentUserId, // Referans olarak gönderen kişinin ID'sini kullanıyoruz
          'status': 'unread',
          'isRead': false,
        },
      );
    } catch (e) {
      print('Arkadaşlık bildirimi gönderilemedi: $e');
    }
  }

  /// İki kullanıcı arasındaki ilişkiyi getirir
  Future<models.Document?> checkFriendshipStatus(String userId1, String userId2) async {
    // 1. Sen gönderdin
    final q1 = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: friendshipsCollectionId,
      queries: [
        Query.equal('followerId', userId1),
        Query.equal('followingId', userId2),
      ],
    );
    if (q1.documents.isNotEmpty) return q1.documents.first;

    // 2. O gönderdi
    final q2 = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: friendshipsCollectionId,
      queries: [
        Query.equal('followerId', userId2),
        Query.equal('followingId', userId1),
      ],
    );
    if (q2.documents.isNotEmpty) return q2.documents.first;

    return null;
  }

  /// Gelen bekleyen istekleri getir
  Future<List<models.Document>> getPendingRequests(String userId) async {
    final res = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: friendshipsCollectionId,
      queries: [
        Query.equal('followingId', userId),
        Query.equal('status', 'pending'),
        Query.orderDesc('\$createdAt'),
      ],
    );
    return res.documents;
  }

  /// Kabul edilmiş arkadaşları getir
  Future<List<models.Document>> getFriends(String userId) async {
    // 1. Kullanıcının isteği gönderdiği ve kabul edilenler
    final q1 = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: friendshipsCollectionId,
      queries: [
        Query.equal('followerId', userId),
        Query.equal('status', 'accepted'),
      ],
    );

    // 2. Kullanıcıya gelen ve kabul edilenler
    final q2 = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: friendshipsCollectionId,
      queries: [
        Query.equal('followingId', userId),
        Query.equal('status', 'accepted'),
      ],
    );

    return [...q1.documents, ...q2.documents];
  }

  /// Kullanıcı ID'sine göre isteği kabul et (Bildirim ekranı için pratik)
  Future<void> acceptRequestFromUser(String currentUserId, String senderId) async {
    final doc = await checkFriendshipStatus(currentUserId, senderId);
    if (doc != null) {
      await acceptRequest(doc.$id);
      
      // ✅ İki tarafa da "Artık arkadaşsınız" bildirimi gönder
      try {
        // İsimleri alalım (Bildirim metni için)
        final currentUserDoc = await _databases.getDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.usersCollectionId,
          documentId: currentUserId,
        );
        final senderDoc = await _databases.getDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.usersCollectionId,
          documentId: senderId,
        );

        final currentUserName = currentUserDoc.data['displayName'] ?? 'Bir kullanıcı';
        final senderName = senderDoc.data['displayName'] ?? 'Bir kullanıcı';

        // 1. İsteği gönderen kişiye bildirim (Senin isteğini kabul etti)
        await _notificationService.createNotification(
          toUserId: senderId,
          fromUserId: currentUserId,
          type: 'friend_accepted',
          content: '$currentUserName arkadaşlık isteğini kabul etti. Artık arkadaşsınız!',
          eventId: currentUserId,
        );

        // 2. İsteği kabul eden kişiye bildirim (Artık arkadaşsınız)
        await _notificationService.createNotification(
          toUserId: currentUserId,
          fromUserId: senderId,
          type: 'friend_accepted',
          content: '$senderName ile artık arkadaşsınız.',
          eventId: senderId,
        );
      } catch (e) {
        print('Arkadaşlık kabul bildirimi hatası: $e');
      }
    }
  }

  /// Kullanıcı ID'sine göre isteği reddet
  Future<void> rejectRequestFromUser(String currentUserId, String senderId) async {
    final doc = await checkFriendshipStatus(currentUserId, senderId);
    if (doc != null) {
      await deleteRequest(doc.$id);
    }
  }

  /// İsteği kabul et
  Future<void> acceptRequest(String documentId) async {
    await _databases.updateDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: friendshipsCollectionId,
      documentId: documentId,
      data: {
        'status': 'accepted',
      },
    );
  }

  /// İsteği reddet veya sil
  Future<void> deleteRequest(String documentId) async {
    await _databases.deleteDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: friendshipsCollectionId,
      documentId: documentId,
    );
  }
}