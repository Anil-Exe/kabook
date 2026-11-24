import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/appwrite_config.dart';
import '../../services/appwrite_service.dart';

final searchServiceProvider = Provider<SearchService>((ref) {
  return SearchService(AppwriteService.client);
});

class SearchService {
  final Databases _databases;

  SearchService(Client client) : _databases = Databases(client);

  /// Kullanıcı Ara (displayName üzerinden)
  Future<List<models.Document>> searchUsers(String query) async {
    if (query.isEmpty) return [];
    
    try {
      final result = await _databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        queries: [
          Query.search('displayName', query),
        ],
      );
      
      // 🟢 DEDUPLICATION: userId'ye göre filtrele (En güncel olanı al)
      final Map<String, models.Document> uniqueDocs = {};
      
      for (var doc in result.documents) {
        final userId = doc.data['userId'] as String?;
        if (userId == null) continue;

        if (!uniqueDocs.containsKey(userId)) {
          uniqueDocs[userId] = doc;
        } else {
          // Eğer listede varsa, tarih karşılaştırıp güncel olanı tut
          final currentDoc = uniqueDocs[userId]!;
          final currentCreatedAt = DateTime.parse(currentDoc.$createdAt);
          final newCreatedAt = DateTime.parse(doc.$createdAt);

          if (newCreatedAt.isAfter(currentCreatedAt)) {
            uniqueDocs[userId] = doc;
          }
        }
      }

      return uniqueDocs.values.toList();
    } catch (e) {
      // Index oluşturulmamışsa hata verebilir, boş liste dönüyoruz
      print('Search users error: $e');
      return [];
    }
  }

  /// Gönderi Ara (content üzerinden)
  Future<List<models.Document>> searchPosts(String query) async {
    if (query.isEmpty) return [];

    try {
      final result = await _databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.postsCollectionId,
        queries: [
          Query.search('content', query),
          Query.orderDesc('\$createdAt'),
        ],
      );
      return result.documents;
    } catch (e) {
      print('Search posts error: $e');
      return [];
    }
  }
}