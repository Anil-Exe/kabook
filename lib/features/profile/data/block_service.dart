import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/appwrite_config.dart';
import '../../../services/appwrite_service.dart';

final blockServiceProvider = Provider<BlockService>((ref) {
  return BlockService();
});

class BlockService {
  final Databases _databases = AppwriteService.databases;

  /// 🚫 Kullanıcıyı Engelle
  Future<void> blockUser({required String currentUserId, required String targetUserId}) async {
    await _databases.createDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.blocksCollectionId,
      documentId: ID.unique(),
      data: {
        'blockerId': currentUserId,
        'blockedId': targetUserId,
      },
      permissions: [
        Permission.read(Role.user(currentUserId)),
        Permission.delete(Role.user(currentUserId)),
      ]
    );
  }

  /// ✅ Engeli Kaldır
  Future<void> unblockUser({required String blockDocId}) async {
    await _databases.deleteDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.blocksCollectionId,
      documentId: blockDocId,
    );
  }
  
  /// 🔍 Engelleme Durumunu Kontrol Et
  Future<Document?> getBlockDocument(String currentUserId, String targetUserId) async {
     final res = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.blocksCollectionId,
      queries: [
        Query.equal('blockerId', currentUserId),
        Query.equal('blockedId', targetUserId),
      ],
    );
    if (res.documents.isNotEmpty) return res.documents.first;
    return null;
  }
}