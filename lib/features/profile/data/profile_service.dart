import 'dart:io';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/appwrite_config.dart';
import '../../../services/appwrite_service.dart';
import '../../../services/image_upload_service.dart';

final profileServiceProvider = Provider<ProfileService>((ref) {
  return ProfileService();
});

class ProfileService {
  final Databases _databases = AppwriteService.databases;
  final Storage _storage = Storage(AppwriteService.client); // Storage ekledik
  final Account _account = Account(AppwriteService.client); // User ID için

  /// 👤 EN GÜNCEL PROFİLİ GETİR (Append-Only için)
  Future<Map<String, dynamic>?> getLatestProfile(String userId) async {
    try {
      final res = await _databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.usersCollectionId,
        queries: [
          Query.equal('userId', userId),
          Query.orderDesc('\$createdAt'), // En son oluşturulanı al
          Query.limit(1),
        ],
      );
      if (res.documents.isEmpty) return null;
      return res.documents.first.data;
    } catch (_) {
      return null;
    }
  }

  /// 👤 PROFİL GETİR
  Future<Map<String, dynamic>?> getProfile(String userId) async {
    try {
      // 🟢 DÜZELTME: getDocument yerine getLatestProfile kullanıyoruz (Append-Only uyumu)
      return await getLatestProfile(userId);
    } catch (e) {
      // Profil yoksa null döner
      return null;
    }
  }

  /// 📝 PROFİL OLUŞTUR (ilk login sonrası)
  Future<void> createProfile({
    required String userId,
    required String email,
  }) async {
    await _databases.createDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.usersCollectionId,
      documentId: userId,
      data: {
        'email': email,
        'bio': '',
        'photoId': null, // 🟢 URL yok, ID var
        'createdAt': DateTime.now().toIso8601String(),
      },
      permissions: [
        Permission.read(Role.any()),
        Permission.update(Role.user(userId)),
      ],
    );
  }

  /// ✏️ PROFİL GÜNCELLE (Append-Only / Versioning)
  /// Update izni olmadığı için, mevcut verileri alıp yeni bir belge oluşturuyoruz.
  Future<void> createProfileVersion({
    required String userId,
    required Map<String, dynamic> oldProfileData,
    String? newBio,
    String? newPhotoId, // 🟢 URL yerine ID
  }) async {
    // Eski verileri kopyala
    final data = Map<String, dynamic>.from(oldProfileData);
    
    // Sistem alanlarını temizle (Appwrite bunları kabul etmez)
    data.remove('\$id');
    data.remove('\$createdAt');
    data.remove('\$updatedAt');
    data.remove('\$permissions');
    data.remove('\$collectionId');
    data.remove('\$databaseId');

    // Yeni değerleri ata
    if (newBio != null) data['bio'] = newBio;
    if (newPhotoId != null) data['photoId'] = newPhotoId;
    
    // Yeni versiyon oluştur
    await _databases.createDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.usersCollectionId,
      documentId: ID.unique(), // Her güncelleme yeni bir ID
      data: data,
      permissions: [
        Permission.read(Role.any()), // Herkes okuyabilir
      ],
    );
  }

  /// 🖼️ PROFİL FOTOĞRAFI YÜKLE (Storage'a)
  Future<String> uploadProfilePhoto(XFile pickedFile) async {
    final file = await MediaService.createInputFile(pickedFile);

    final models.File uploadedFile = await _storage.createFile(
      bucketId: AppwriteConfig.storageBucketId, // 'demo_storageBucketId'
      fileId: ID.unique(),
      file: file,
    );

    // 🟢 Sadece ID dönüyoruz
    return uploadedFile.$id;
  }

  /// 🗑️ ESKİ PROFİL FOTOĞRAFI SİL
  Future<void> deleteOldProfilePhoto(String? oldPhotoId) async {
    if (oldPhotoId == null || oldPhotoId.isEmpty) return;

    try {
      await _storage.deleteFile(
        bucketId: AppwriteConfig.storageBucketId,
        fileId: oldPhotoId,
      );
    } catch (e) {
      print('Eski fotoğraf silinemedi: $e');
    }
  }
}
