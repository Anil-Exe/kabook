import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabook_app/core/config/appwrite_config.dart';
import 'package:kabook_app/services/appwrite_service.dart';
import '../../follow/data/follow_service.dart';

final blockServiceProvider = Provider((ref) {
  return BlockService(
    databases: AppwriteService.databases,
    followService: ref.read(followServiceProvider),
  );
});

/// 🚫 Engelleme Durumu Provider'ı (Profil sayfasında kullanılır)
/// Return: [DidIBlockThem, DidTheyBlockMe]
final blockStatusProvider = FutureProvider.family<List<bool>, String>((ref, combinedIds) async {
  final service = ref.read(blockServiceProvider);
  final ids = combinedIds.split('|');
  final currentUserId = ids[0];
  final targetUserId = ids[1];

  final didIBlock = await service.hasBlocked(blockerId: currentUserId, blockedId: targetUserId);
  final didTheyBlock = await service.hasBlocked(blockerId: targetUserId, blockedId: currentUserId);

  return [didIBlock, didTheyBlock];
});

/// 📋 Engellenen Kullanıcılar Listesi Provider'ı
final blockedUsersProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, userId) async {
  return ref.read(blockServiceProvider).getBlockedUsers(userId);
});

class BlockService {
  final Databases _databases;
  final FollowService _followService;
  final String _dbId = AppwriteConfig.databaseId;
  final String _collectionId = 'blocks'; // setup.js'deki ID

  BlockService({required Databases databases, required FollowService followService})
      : _databases = databases,
        _followService = followService;

  /// 🚫 Kullanıcıyı Engelle
  Future<void> blockUser({required String currentUserId, required String targetUserId}) async {
    try {
      // 1. Engelleme kaydı oluştur
      await _databases.createDocument(
        databaseId: _dbId,
        collectionId: _collectionId,
        documentId: ID.unique(),
        data: {
          'blockerId': currentUserId,
          'blockedId': targetUserId,
        },
      );

      // 2. Varsa takipleşmeyi karşılıklı bitir
      await _followService.forceUnfollowBothWays(user1: currentUserId, user2: targetUserId);

      // 3. Sayaçları garantiye al (Yeniden hesapla)
      await _followService.recalculateFollowCounts(currentUserId);
      await _followService.recalculateFollowCounts(targetUserId);

    } on AppwriteException catch (e) {
      if (e.code == 409) return; // Zaten engelli
      rethrow;
    }
  }

  /// ✅ Engeli Kaldır
  Future<void> unblockUser({required String currentUserId, required String targetUserId}) async {
    // Tüm eşleşen engelleri bul (Duplicate varsa hepsini silmek için)
    final res = await _databases.listDocuments(
      databaseId: _dbId,
      collectionId: _collectionId,
      queries: [
        Query.equal('blockerId', currentUserId),
        Query.equal('blockedId', targetUserId),
      ],
    );

    // Bulunan tüm kayıtları sil (Böylece 20 tane varsa hepsi temizlenir)
    for (var doc in res.documents) {
      await _databases.deleteDocument(
        databaseId: _dbId,
        collectionId: _collectionId,
        documentId: doc.$id,
      );
    }
  }

  /// 📋 Engellenen Kullanıcıları Getir
  Future<List<Map<String, dynamic>>> getBlockedUsers(String currentUserId) async {
    try {
      // 1. Engelleme kayıtlarını çek
      final blocksRes = await _databases.listDocuments(
        databaseId: _dbId,
        collectionId: _collectionId,
        queries: [Query.equal('blockerId', currentUserId)],
      );

      if (blocksRes.documents.isEmpty) return [];

      // 2. Engellenen ID'leri listele ve TEKRARLARI TEMİZLE (.toSet())
      final blockedIds = blocksRes.documents.map((doc) => doc.data['blockedId'] as String).toSet().toList();

      if (blockedIds.isEmpty) return [];

      // 3. Kullanıcı detaylarını çek
      final usersRes = await _databases.listDocuments(
        databaseId: _dbId,
        collectionId: AppwriteConfig.usersCollectionId,
        queries: [Query.equal('userId', blockedIds)],
      );

      return usersRes.documents.map((doc) => doc.data).toList();
    } catch (e) {
      print('Get blocked users error: $e');
      return [];
    }
  }

  /// ⚡ Engellenen Kullanıcı ID'lerini Getir (Hızlı Filtreleme İçin)
  Future<List<String>> getBlockedUserIds(String currentUserId) async {
    try {
      final blocksRes = await _databases.listDocuments(
        databaseId: _dbId,
        collectionId: _collectionId,
        queries: [Query.equal('blockerId', currentUserId)],
      );
      return blocksRes.documents.map((doc) => doc.data['blockedId'] as String).toSet().toList();
    } catch (e) {
      return [];
    }
  }

  /// 🔍 Engelleme Kontrolü
  Future<bool> hasBlocked({required String blockerId, required String blockedId}) async {
    try {
      final res = await _databases.listDocuments(
        databaseId: _dbId,
        collectionId: _collectionId,
        queries: [
          Query.equal('blockerId', blockerId),
          Query.equal('blockedId', blockedId),
          Query.limit(1),
        ],
      );
      return res.documents.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}
