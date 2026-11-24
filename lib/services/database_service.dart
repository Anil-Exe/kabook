import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import '../core/config/appwrite_config.dart';
import 'appwrite_service.dart';

/// Veritabanı servisi - CRUD işlemleri
class DatabaseService {
  final Databases _databases = AppwriteService.databases;

  /// Belge oluştur
  Future<models.Document> createDocument({
    required String collectionId,
    required Map<String, dynamic> data,
    List<String>? permissions,
  }) async {
    try {
      return await _databases.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: collectionId,
        documentId: ID.unique(),
        data: data,
        permissions: permissions ?? [],
      );
    } on AppwriteException catch (e) {
      throw Exception('Belge oluşturulamadı: ${e.message}');
    }
  }

  /// Belge güncelle
  Future<models.Document> updateDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    try {
      return await _databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: collectionId,
        documentId: documentId,
        data: data,
      );
    } on AppwriteException catch (e) {
      throw Exception('Belge güncellenemedi: ${e.message}');
    }
  }

  /// Belge sil
  Future<void> deleteDocument({
    required String collectionId,
    required String documentId,
  }) async {
    try {
      await _databases.deleteDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: collectionId,
        documentId: documentId,
      );
    } on AppwriteException catch (e) {
      throw Exception('Belge silinemedi: ${e.message}');
    }
  }

  /// Belge al
  Future<models.Document> getDocument({
    required String collectionId,
    required String documentId,
  }) async {
    try {
      return await _databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: collectionId,
        documentId: documentId,
      );
    } on AppwriteException catch (e) {
      throw Exception('Belge alınamadı: ${e.message}');
    }
  }

  /// Belge listesi al
  Future<models.DocumentList> listDocuments({
    required String collectionId,
    List<String>? queries,
    int? limit,
    int? offset,
  }) async {
    try {
      final finalQueries = <String>[
        ...(queries ?? []),
        if (limit != null) Query.limit(limit),
        if (offset != null) Query.offset(offset),
      ];

      return await _databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: collectionId,
        queries: finalQueries,
      );
    } on AppwriteException catch (e) {
      throw Exception('Belgeler alınamadı: ${e.message}');
    }
  }

  /// Kullanıcı belgesi al (userId ile)
  Future<models.Document?> getUserDocument(String userId) async {
    try {
      final result = await listDocuments(
        collectionId: AppwriteConfig.usersCollectionId,
        queries: [Query.equal('userId', userId)],
        limit: 1,
      );
      if (result.documents.isNotEmpty) {
        return result.documents.first;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Gönderi oluştur
  Future<models.Document> createPost({
    required String userId,
    required String content,
    String? imageId,
  }) async {
    return await createDocument(
      collectionId: AppwriteConfig.postsCollectionId,
      data: {
        'userId': userId,
        'content': content,
        'imageId': imageId,
        'likesCount': 0,
        'commentsCount': 0,
        'sharesCount': 0,
        // createdAt kaldırıldı
        'likedBy': <String>[],
      },
      permissions: [
        Permission.read(Role.any()),
        Permission.update(Role.user(userId)),
        Permission.delete(Role.user(userId)),
      ],
    );
  }

  /// Gönderi listesi al (sondan başa sıralı)
  Future<List<models.Document>> getPosts({int limit = 25}) async {
    try {
      final result = await listDocuments(
        collectionId: AppwriteConfig.postsCollectionId,
        queries: [
          Query.orderDesc('\$createdAt'), // Changed to system attribute
        ],
        limit: limit,
      );
      return result.documents;
    } catch (e) {
      return [];
    }
  }

  /// Kullanıcının gönderilerini al
  Future<List<models.Document>> getUserPosts(String userId, {int limit = 25}) async {
    try {
      final result = await listDocuments(
        collectionId: AppwriteConfig.postsCollectionId,
        queries: [
          Query.equal('userId', userId),
          Query.orderDesc('\$createdAt'), // Changed to system attribute
        ],
        limit: limit,
      );
      return result.documents;
    } catch (e) {
      return [];
    }
  }

  /// Gönderiyi beğen/beğenmeyi kaldır
  Future<void> toggleLikePost({
    required String postId,
    required String userId,
    required bool isLiked,
  }) async {
    try {
      final post = await getDocument(
        collectionId: AppwriteConfig.postsCollectionId,
        documentId: postId,
      );

      final likedBy = List<String>.from(post.data['likedBy'] ?? []);
      final currentLikes = post.data['likesCount'] ?? 0;

      if (isLiked) {
        likedBy.remove(userId);
        await updateDocument(
          collectionId: AppwriteConfig.postsCollectionId,
          documentId: postId,
          data: {
            'likedBy': likedBy,
            'likesCount': currentLikes - 1,
          },
        );
      } else {
        likedBy.add(userId);
        await updateDocument(
          collectionId: AppwriteConfig.postsCollectionId,
          documentId: postId,
          data: {
            'likedBy': likedBy,
            'likesCount': currentLikes + 1,
          },
        );
      }
    } catch (e) {
      throw Exception('Beğeni işlemi başarısız: ${e.toString()}');
    }
  }

  /// Mesaj oluştur
  Future<models.Document> createMessage({
    required String senderId,
    required String receiverId,
    required String content,
  }) async {
    return await createDocument(
      collectionId: AppwriteConfig.messagesCollectionId,
      data: {
        'senderId': senderId,
        'receiverId': receiverId,
        'content': content,
        'isRead': false,
        // createdAt kaldırıldı, Appwrite otomatik ekler ($createdAt)
      },
    );
  }

  /// İki kullanıcı arasındaki mesajları al
  Future<List<models.Document>> getMessages({
    required String userId1,
    required String userId2,
    int limit = 50,
  }) async {
    try {
      final result = await listDocuments(
        collectionId: AppwriteConfig.messagesCollectionId,
        queries: [
          Query.or([
            Query.and([
              Query.equal('senderId', userId1),
              Query.equal('receiverId', userId2),
            ]),
            Query.and([
              Query.equal('senderId', userId2),
              Query.equal('receiverId', userId1),
            ]),
          ]),
          Query.orderDesc('\$createdAt'), // Sistem attribute'u kullanımı
        ],
        limit: limit,
      );
      return result.documents.reversed.toList(); // En eski mesaj üstte
    } catch (e) {
      return [];
    }
  }

  /// Kullanıcının tüm konuşmalarını al
  Future<List<models.Document>> getUserConversations(String userId) async {
    try {
      // Bu sorgu karmaşık olabilir, basitleştirilmiş versiyon
      final sentMessages = await listDocuments(
        collectionId: AppwriteConfig.messagesCollectionId,
        queries: [
          Query.equal('senderId', userId),
        ],
      );

      final receivedMessages = await listDocuments(
        collectionId: AppwriteConfig.messagesCollectionId,
        queries: [
          Query.equal('receiverId', userId),
        ],
      );

      // Benzersiz kullanıcı ID'lerini bul
      final Set<String> userIds = {};
      for (var msg in sentMessages.documents) {
        userIds.add(msg.data['receiverId']);
      }
      for (var msg in receivedMessages.documents) {
        userIds.add(msg.data['senderId']);
      }

      return userIds.map((id) => models.Document(
        data: {'userId': id},
        $id: id,
        $collectionId: '',
        $databaseId: '',
        $createdAt: DateTime.now().toIso8601String(),
        $updatedAt: DateTime.now().toIso8601String(),
        $permissions: [],
      )).toList();
    } catch (e) {
      return [];
    }
  }

  /// Arkadaşlık isteği oluştur
  Future<models.Document> createFriendshipRequest({
    required String requesterId,
    required String requestedId,
  }) async {
    return await createDocument(
      collectionId: AppwriteConfig.friendshipsCollectionId,
      data: {
        'requesterId': requesterId,
        'requestedId': requestedId,
        'status': 'pending', // pending, accepted, rejected
        'createdAt': DateTime.now().toIso8601String(),
      },
      permissions: [
        Permission.read(Role.user(requesterId)),
        Permission.read(Role.user(requestedId)),
        Permission.update(Role.user(requestedId)),
        Permission.delete(Role.user(requesterId)),
      ],
    );
  }

  /// Arkadaşlık durumunu güncelle
  Future<void> updateFriendshipStatus({
    required String friendshipId,
    required String status, // accepted, rejected
  }) async {
    await updateDocument(
      collectionId: AppwriteConfig.friendshipsCollectionId,
      documentId: friendshipId,
      data: {'status': status},
    );
  }

  /// Arkadaşlık durumunu kontrol et
  Future<String?> getFriendshipStatus({
    required String userId1,
    required String userId2,
  }) async {
    try {
      final result = await listDocuments(
        collectionId: AppwriteConfig.friendshipsCollectionId,
        queries: [
          Query.or([
            Query.and([
              Query.equal('requesterId', userId1),
              Query.equal('requestedId', userId2),
            ]),
            Query.and([
              Query.equal('requesterId', userId2),
              Query.equal('requestedId', userId1),
            ]),
          ]),
        ],
        limit: 1,
      );

      if (result.documents.isNotEmpty) {
        return result.documents.first.data['status'] as String?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Kullanıcıyı güncelle
  Future<models.Document> updateUser({
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    return await updateDocument(
      collectionId: AppwriteConfig.usersCollectionId,
      documentId: documentId,
      data: data,
    );
  }
}
