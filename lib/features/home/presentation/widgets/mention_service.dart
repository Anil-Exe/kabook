import 'package:appwrite/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../follow/data/follow_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../../services/appwrite_service.dart';
import '../../../../core/config/appwrite_config.dart';

/// Takip edilen kullanıcıları cache'leyen ve arama yapan provider
final mentionCandidatesProvider = FutureProvider.autoDispose<List<Document>>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser == null) return [];

  final followService = ref.read(followServiceProvider);
  
  // 1. Takip edilenlerin listesini (ilişki dokümanları) çek
  final followingDocs = await followService.getFollowing(currentUser.$id);
  
  if (followingDocs.isEmpty) return [];

  // 2. Takip edilenlerin User ID'lerini al
  final followingIds = followingDocs.map((doc) => doc.data['followingId'] as String).toList();

  // 3. Bu ID'lere sahip kullanıcı profillerini getir (Toplu sorgu)
  // Not: Appwrite Query.equal array kabul eder (IN operatörü gibi çalışır)
  // Maksimum limit kontrolü yapılmalı (Appwrite default limit 25/100)
  if (followingIds.isEmpty) return [];

  final databases = AppwriteService.databases;
  final userDocs = await databases.listDocuments(
    databaseId: AppwriteConfig.databaseId,
    collectionId: AppwriteConfig.usersCollectionId,
    queries: [
      Query.equal('userId', followingIds),
      Query.limit(100), // Makul bir limit
    ],
  );

  return userDocs.documents;
});

/// Filtreleme mantığını yöneten sınıf
class MentionFilterService {
  /// Ham liste içinden query'e göre filtreleme yapar
  static List<Document> filterUsers(List<Document> allUsers, String query) {
    if (query.isEmpty) return allUsers;
    
    final lowerQuery = query.toLowerCase();
    return allUsers.where((doc) {
      final name = (doc.data['displayName'] ?? '').toString().toLowerCase();
      final username = (doc.data['username'] ?? '').toString().toLowerCase();
      
      // İsim veya kullanıcı adı eşleşiyor mu?
      return name.contains(lowerQuery) || username.contains(lowerQuery);
    }).toList();
  }
}

/// UI State için filtrelenmiş listeyi tutan provider
final filteredMentionsProvider = StateProvider.autoDispose<List<Document>>((ref) {
  // Başlangıçta boş
  return [];
});