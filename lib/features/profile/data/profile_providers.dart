import 'package:appwrite/appwrite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/appwrite_config.dart';
import '../../../services/appwrite_service.dart';

final profileServiceProvider = Provider<ProfileService>((ref) {
  return ProfileService();
});

class ProfileService {
  final Databases _databases = AppwriteService.databases;

  /// 👤 PROFİLİ GETİR (SON OLUŞTURULAN)
  Future<Map<String, dynamic>?> getLatestProfile(String userId) async {
    try {
      final res = await _databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        queries: [
          Query.equal('userId', userId),
          Query.orderDesc('\$createdAt'),
          Query.limit(1),
        ],
      );

      if (res.documents.isEmpty) return null;
      return res.documents.first.data;
    } catch (_) {
      return null;
    }
  }

  /// 📝 PROFİL OLUŞTUR (İLK LOGIN)
  Future<void> createProfile({
    required String userId,
    required String email,
    String? university,
    String? faculty,
    String? department,
  }) async {
    await _databases.createDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.usersCollectionId,
      documentId: ID.unique(),
      data: {
        'userId': userId,
        'email': email,
        'bio': '',
        'photoUrl': null,
        'university': university,
        'faculty': faculty,
        'department': department,
      },
      permissions: [
        Permission.read(Role.guests()), // herkes okuyabilir
      ],
    );
  }

  /// ✏️ BIO "GÜNCELLE" (ASLINDA YENİ DOC)
  Future<void> createBioVersion({
    required String userId,
    required String bio,
    Map<String, dynamic>? lastProfile,
  }) async {
    await _databases.createDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.usersCollectionId,
      documentId: ID.unique(),
      data: {
        'userId': userId,
        'email': lastProfile?['email'],
        'bio': bio,
        'photoUrl': lastProfile?['photoUrl'],
        'university': lastProfile?['university'],
        'faculty': lastProfile?['faculty'],
        'department': lastProfile?['department'],
      },
      permissions: [
        Permission.read(Role.guests()),
      ],
    );
  }

  /// 🖼️ PROFİL FOTO "GÜNCELLE" (YENİ DOC)
  Future<void> createProfilePhotoVersion({
    required String userId,
    required String photoUrl,
    Map<String, dynamic>? lastProfile,
  }) async {
    await _databases.createDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.usersCollectionId,
      documentId: ID.unique(),
      data: {
        'userId': userId,
        'email': lastProfile?['email'],
        'bio': lastProfile?['bio'],
        'photoUrl': photoUrl,
        'university': lastProfile?['university'],
        'faculty': lastProfile?['faculty'],
        'department': lastProfile?['department'],
      },
      permissions: [
        Permission.read(Role.guests()),
      ],
    );
  }
}
