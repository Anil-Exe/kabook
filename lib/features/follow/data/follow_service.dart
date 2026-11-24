import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabook_app/core/config/appwrite_config.dart';
import 'package:kabook_app/services/appwrite_service.dart';
import '../../notifications/data/notification_service.dart';
import '../../auth/data/auth_providers.dart';

final followServiceProvider = Provider((ref) {
  return FollowService(
    databases: Databases(AppwriteService.client),
    notificationService: ref.read(notificationServiceProvider),
  );
});

// Realtime Takip Dinleyicisi
final followRealtimeProvider = StreamProvider.autoDispose((ref) {
  final realtime = AppwriteService.realtime;
  return realtime.subscribe([
    'databases.${AppwriteConfig.databaseId}.collections.follows.documents'
  ]).stream;
});

// 🆕 Gizlilik Kontrolü Provider'ı
final canViewProfileProvider = FutureProvider.family<bool, String>((ref, targetUserId) async {
  final currentUser = ref.watch(currentUserProvider).value;
  if (currentUser == null) return false;
  
  return ref.read(followServiceProvider).canViewProfile(
    currentUserId: currentUser.$id,
    targetUserId: targetUserId,
  );
});

class FollowService {
  final Databases _databases;
  final NotificationService _notificationService;
  final String _dbId = AppwriteConfig.databaseId;
  final String _collectionId = AppwriteConfig.followsCollectionId;
  final String _usersCollectionId = 'users';

  FollowService({required Databases databases, required NotificationService notificationService})
      : _databases = databases,
        _notificationService = notificationService;

  // Takip Et
  Future<void> followUser({required String currentUserId, required String targetUserId}) async {
    // Hedef kullanıcının gizlilik durumunu kontrol et
    // 🟢 DÜZELTME: getDocument yerine listDocuments kullanıyoruz.
    // Profil düzenleme sonrası Document ID değişmiş olabilir (Append-Only mimarisi).
    // Bu yüzden userId alanına göre sorgulayıp en güncel dokümanı alıyoruz.
    final userDocs = await _databases.listDocuments(
      databaseId: _dbId,
      collectionId: _usersCollectionId,
      queries: [
        Query.equal('userId', targetUserId),
        Query.orderDesc('\$createdAt'),
        Query.limit(1),
      ],
    );

    // Kullanıcı bulunamazsa varsayılan olarak 'public' (false) kabul edelim
    final isPrivate = userDocs.documents.isNotEmpty 
        ? (userDocs.documents.first.data['isPrivate'] ?? false) 
        : false;
        
    final status = isPrivate ? 'pending' : 'approved';

    try {
      await _databases.createDocument(
        databaseId: _dbId,
        collectionId: _collectionId,
        documentId: ID.unique(),
        data: {
          'followerId': currentUserId,
          'followingId': targetUserId,
          'status': status,
          'followedAt': DateTime.now().toIso8601String(),
        },
        
      );

      // 🆕 SAYAÇ GÜNCELLEME: Takip edilen kişinin takipçi sayısını artır
      if (status == 'approved') {
        await recalculateFollowCounts(targetUserId);
        await recalculateFollowCounts(currentUserId);
      }
    } on AppwriteException catch (e) {
      // 409: Conflict (Zaten takip ediliyor)
      if (e.code == 409) {
        return; // İşlemi başarılı say ve çık (Bildirim gönderme)
      }
      rethrow; // Diğer hataları fırlat
    }

    // 🔔 BİLDİRİM GÖNDER
    try {
      // Bildirim metni için takip eden kişinin ismini çek
      final currentUserDoc = await _databases.getDocument(
        databaseId: _dbId,
        collectionId: _usersCollectionId,
        documentId: currentUserId,
      );
      final currentUserName = currentUserDoc.data['displayName'] ?? 'Bir kullanıcı';

      if (status == 'approved') {
        await _notificationService.createNotification(
          toUserId: targetUserId,
          fromUserId: currentUserId,
          type: 'follow',
          content: '$currentUserName sizi takip etmeye başladı',
          eventId: currentUserId,
        );
      } else {
        await _notificationService.createNotification(
          toUserId: targetUserId,
          fromUserId: currentUserId,
          type: 'follow_request',
          content: '$currentUserName sizi takip etmek istiyor',
          eventId: currentUserId,
        );
      }
    } catch (e) {
      print('Takip bildirimi gönderilemedi: $e');
    }
  }

  // Takipten Çık / İsteği İptal Et
  Future<void> unfollowUser({required String followDocId}) async {
    // Önce dokümanı al ki kimin kimi takip ettiğini bilelim (sayaç düşmek için)
    final doc = await _databases.getDocument(
      databaseId: _dbId,
      collectionId: _collectionId,
      documentId: followDocId,
    );

    await _databases.deleteDocument(
      databaseId: _dbId,
      collectionId: _collectionId,
      documentId: followDocId,
    );

    // 🆕 SAYAÇ GÜNCELLEME: Eğer onaylı bir takip ise sayaçları düşür
    if (doc.data['status'] == 'approved') {
      await recalculateFollowCounts(doc.data['followingId']);
      await recalculateFollowCounts(doc.data['followerId']);
    }
  }

  // Takipçiyi Çıkar (Profil sahibi takipçisini siliyor)
  Future<void> removeFollower(String followDocId) async {
    await _databases.deleteDocument(
      databaseId: _dbId,
      collectionId: _collectionId,
      documentId: followDocId,
    );
    
    // Doküman silindiği için ID'den veriyi çekemeyiz, bu metodun parametresi olarak
    // userId'leri almak daha sağlıklı olurdu ama şimdilik basit tutuyoruz.
    // Not: Bu metodun kullanıldığı yerde sayaçları güncellemek için 
    // forceUnfollowBothWays mantığına benzer bir yapı kurulmalı veya 
    // UI tarafında refresh yapılmalı. Ancak forceUnfollowBothWays aşağıda düzeltildi.
  }

  // Takip İsteğini Kabul Et
  Future<void> acceptRequest(String followDocId) async {
    // 1. Dokümanı getir (followerId ve followingId lazım)
    final doc = await _databases.getDocument(
      databaseId: _dbId,
      collectionId: _collectionId,
      documentId: followDocId,
    );

    // 2. Durumu güncelle
    await _databases.updateDocument(
      databaseId: _dbId,
      collectionId: _collectionId,
      documentId: followDocId,
      data: {'status': 'approved'},
    );

    // 🆕 SAYAÇ GÜNCELLEME: İstek onaylandı, sayıları artır
    await recalculateFollowCounts(doc.data['followingId']);
    await recalculateFollowCounts(doc.data['followerId']);

    // 3. Bildirim Gönder (İsteği gönderen kişiye: "X isteğini kabul etti")
    try {
      final followerId = doc.data['followerId'];
      final followingId = doc.data['followingId']; // Bu işlemi yapan kişi (kabul eden)

      // Kabul eden kişinin ismini al (Append-only mimarisi için sorgu ile)
      final userDocs = await _databases.listDocuments(
        databaseId: _dbId,
        collectionId: _usersCollectionId,
        queries: [
          Query.equal('userId', followingId),
          Query.orderDesc('\$createdAt'),
          Query.limit(1),
        ],
      );
      
      final currentUserName = userDocs.documents.isNotEmpty 
          ? (userDocs.documents.first.data['displayName'] ?? 'Bir kullanıcı')
          : 'Bir kullanıcı';

      await _notificationService.createNotification(
        toUserId: followerId,
        fromUserId: followingId,
        type: 'follow_accepted',
        content: '$currentUserName takip isteğini kabul etti',
        eventId: followingId,
      );
    } catch (e) {
      print('Takip kabul bildirimi hatası: $e');
    }
  }

  // Takip Durumunu Kontrol Et (Current User -> Target User)
  Future<Document?> getFollowStatus(String currentUserId, String targetUserId) async {
    final result = await _databases.listDocuments(
      databaseId: _dbId,
      collectionId: _collectionId,
      queries: [
        Query.equal('followerId', currentUserId),
        Query.equal('followingId', targetUserId),
      ],
    );
    return result.documents.isNotEmpty ? result.documents.first : null;
  }

  // Takipçi Sayısı (Real-time için query)
  Future<int> getFollowersCount(String userId) async {
    final result = await _databases.listDocuments(
      databaseId: _dbId,
      collectionId: _collectionId,
      queries: [
        Query.equal('followingId', userId),
        Query.equal('status', 'approved'),
        Query.limit(1), // Sadece sayıyı almak için
      ],
    );
    return result.total;
  }

  // Takip Edilen Sayısı
  Future<int> getFollowingCount(String userId) async {
    final result = await _databases.listDocuments(
      databaseId: _dbId,
      collectionId: _collectionId,
      queries: [
        Query.equal('followerId', userId),
        Query.equal('status', 'approved'),
        Query.limit(1),
      ],
    );
    return result.total;
  }

  // Takipçileri Getir (Liste)
  Future<List<Document>> getFollowers(String userId) async {
    final result = await _databases.listDocuments(
      databaseId: _dbId,
      collectionId: _collectionId,
      queries: [
        Query.equal('followingId', userId),
        Query.equal('status', 'approved'),
        Query.orderDesc('followedAt'),
      ],
    );
    return result.documents;
  }

  // Takip Edilenleri Getir (Liste)
  Future<List<Document>> getFollowing(String userId) async {
    final result = await _databases.listDocuments(
      databaseId: _dbId,
      collectionId: _collectionId,
      queries: [
        Query.equal('followerId', userId),
        Query.equal('status', 'approved'),
        Query.orderDesc('followedAt'),
      ],
    );
    return result.documents;
  }

  /// ⚡ Takip Edilenlerin ID Listesini Getir (Hızlı Kontrol İçin)
  Future<List<String>> getFollowingIds(String userId) async {
    final docs = await getFollowing(userId);
    return docs.map((doc) => doc.data['followingId'] as String).toList();
  }

  // Bekleyen İstekleri Getir (Bana gelenler)
  Future<List<Document>> getPendingRequests(String currentUserId) async {
    final result = await _databases.listDocuments(
      databaseId: _dbId,
      collectionId: _collectionId,
      queries: [
        Query.equal('followingId', currentUserId),
        Query.equal('status', 'pending'),
        Query.orderDesc('followedAt'),
      ],
    );
    return result.documents;
  }

  // 🔍 Takip Listesinde Arama Yap
  Future<List<Document>> searchInFollowList({
    required String userId,
    required String type, // 'followers' veya 'following'
    required String query,
  }) async {
    try {
      // 1. Önce hedeflenen kullanıcı ID'lerini bul (Takip ettiklerim veya Takipçilerim)
      List<String> targetIds = [];
      
      if (type == 'followers') {
        final followers = await getFollowers(userId);
        targetIds = followers.map((doc) => doc.data['followerId'] as String).toList();
      } else {
        final following = await getFollowing(userId);
        targetIds = following.map((doc) => doc.data['followingId'] as String).toList();
      }

      if (targetIds.isEmpty) return [];

      // 2. Bu ID'lere sahip kullanıcı profillerini getir
      // Not: Appwrite'da Query.equal array kabul eder (IN operatorü gibi çalışır)
      final userResults = await _databases.listDocuments(
        databaseId: _dbId,
        collectionId: _usersCollectionId,
        queries: [
          Query.equal('userId', targetIds),
          // Query.search KALDIRILDI: Index hatasını önlemek için filtrelemeyi aşağıda yapıyoruz
          Query.limit(100), 
        ],
      );

      // Client-side filtreleme (İsim veya kullanıcı adına göre)
      if (query.isNotEmpty) {
        final lowerQuery = query.toLowerCase();
        return userResults.documents.where((doc) {
          final name = (doc.data['displayName'] ?? '').toString().toLowerCase();
          final username = (doc.data['username'] ?? '').toString().toLowerCase();
          return name.contains(lowerQuery) || username.contains(lowerQuery);
        }).toList();
      }

      return userResults.documents;
    } catch (e) {
      print('Search error: $e');
      return [];
    }
  }

  /// 🔒 Profil Görüntüleme İzni Kontrolü
  /// Gizli hesap ise ve takip edilmiyorsa false döner
  Future<bool> canViewProfile({required String currentUserId, required String targetUserId}) async {
    // Kendi profilimizse her zaman görüntüleyebiliriz
    if (currentUserId == targetUserId) return true;

    try {
      // 1. Hedef kullanıcının gizlilik ayarını al
      final userDocs = await _databases.listDocuments(
        databaseId: _dbId,
        collectionId: _usersCollectionId,
        queries: [
          Query.equal('userId', targetUserId),
          Query.orderDesc('\$createdAt'),
          Query.limit(1),
        ],
      );

      if (userDocs.documents.isEmpty) return false;

      final isPrivate = userDocs.documents.first.data['isPrivate'] ?? false;

      // Hesap herkese açıksa görüntüle
      if (!isPrivate) return true;

      // 2. Hesap gizliyse takip durumuna bak (Approved olmalı)
      final followDoc = await getFollowStatus(currentUserId, targetUserId);
      
      return followDoc != null && followDoc.data['status'] == 'approved';
    } catch (e) {
      print('Privacy check error: $e');
      return false;
    }
  }

  /// 🚫 Karşılıklı Takipten Çıkar (Engelleme durumunda kullanılır)
  Future<void> forceUnfollowBothWays({required String user1, required String user2}) async {
    try {
      // User1 -> User2 ilişkisini bul ve sil
      final doc1 = await getFollowStatus(user1, user2);
      if (doc1 != null) {
        await _databases.deleteDocument(
          databaseId: _dbId,
          collectionId: _collectionId,
          documentId: doc1.$id,
        );
        // Eğer onaylıysa sayaç düş
        if (doc1.data['status'] == 'approved') {
          await recalculateFollowCounts(user2);
          await recalculateFollowCounts(user1);
        }
      }

      // User2 -> User1 ilişkisini bul ve sil
      final doc2 = await getFollowStatus(user2, user1);
      if (doc2 != null) {
        await _databases.deleteDocument(
          databaseId: _dbId,
          collectionId: _collectionId,
          documentId: doc2.$id,
        );
        if (doc2.data['status'] == 'approved') {
          await recalculateFollowCounts(user1);
          await recalculateFollowCounts(user2);
        }
      }
    } catch (e) {
      print('Force unfollow error: $e');
    }
  }

  /// 🔢 Yardımcı Fonksiyon: Kullanıcı Sayaçlarını Güncelle
  Future<void> _updateUserCounts(String userId, {int followersChange = 0, int followingChange = 0}) async {
    try {
      final userDoc = await _databases.getDocument(
        databaseId: _dbId,
        collectionId: _usersCollectionId,
        documentId: userId,
      );

      final currentFollowers = userDoc.data['followersCount'] ?? 0;
      final currentFollowing = userDoc.data['followingCount'] ?? 0;

      await _databases.updateDocument(
        databaseId: _dbId,
        collectionId: _usersCollectionId,
        documentId: userId,
        data: {
          'followersCount': (currentFollowers + followersChange).clamp(0, 999999),
          'followingCount': (currentFollowing + followingChange).clamp(0, 999999),
        },
      );
    } catch (e) {
      print('Sayaç güncelleme hatası: $e');
    }
  }

  /// 🔄 Sayaçları Sıfırdan Hesapla (Engel/Hata durumlarında düzeltmek için)
  Future<void> recalculateFollowCounts(String userId) async {
    try {
      final followers = await getFollowersCount(userId);
      final following = await getFollowingCount(userId);

      await _databases.updateDocument(
        databaseId: _dbId,
        collectionId: _usersCollectionId,
        documentId: userId,
        data: {
          'followersCount': followers,
          'followingCount': following,
        },
      );
    } catch (e) {
      print('Recalculate error: $e');
    }
  }
}
