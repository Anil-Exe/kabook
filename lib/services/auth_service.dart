// lib/services/auth_service.dart

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import '../core/config/appwrite_config.dart';
import 'appwrite_service.dart';
import 'package:kabook_app/utils/user_role_helper.dart'; // ← YENİ: Tek kaynaktan geliyor
import 'image_upload_service.dart';

/// Kimlik doğrulama servisi
class AuthService {
  final Account _account = AppwriteService.account;
  final Databases _databases = AppwriteService.databases;
  final Storage _storage = AppwriteService.storage;

  static const String databaseId = AppwriteConfig.databaseId; // demo_databaseId
  static const String usersCollectionId = AppwriteConfig.usersCollectionId; // users

  /// Email ve şifre ile kayıt ol (akademik bilgilerle)
  Future<models.User> registerWithEmailPassword({
    required String email,
    required String password,
    required String fullName,
    required String username, // 🆕 Kullanıcı adı parametresi eklendi
    required String faculty,
    required String department,
    String university = 'Kastamonu Üniversitesi',
  }) async {
    try {
      // Rol tespiti artık utils/user_role_helper.dart'tan geliyor
      final roleEnum = UserRoleHelper.getRoleFromEmail(email);
      if (roleEnum == null) {
        throw Exception(UserRoleHelper.getInvalidEmailMessage());
      }

      final String roleString = UserRoleHelper.roleToString(roleEnum);

      // 1. Kullanıcı adı müsait mi kontrol et (Account oluşturmadan önce)
      final isUsernameTaken = await checkUsernameAvailability(username);
      if (!isUsernameTaken) {
        throw Exception('Bu kullanıcı adı zaten kullanımda.');
      }

      // Appwrite Account oluştur
      final models.User appwriteUser = await _account.create(
        userId: ID.unique(),
        email: email,
        password: password,
        name: fullName,
      );

      // Otomatik giriş (session)
      await _account.createEmailPasswordSession(email: email, password: password);

      // Profil dokümanı oluştur (documentId = account $id)
      await _databases.createDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: appwriteUser.$id,
        data: {
          'userId': appwriteUser.$id,
          'email': email,
          'username': username, // 🟢 Girilen kullanıcı adı kaydediliyor
          'displayName': fullName,
          'bio': '',
          'photoId': null, // 🟢 URL yerine ID
          'role': roleString,
          'university': university,
          'faculty': faculty,
          'department': department,
          'followersCount': 0,
          'followingCount': 0,
          'postsCount': 0,
          // 'createdAt': ... ❌ Appwrite otomatik ekler
        },
        permissions: [
          Permission.read(Role.user(appwriteUser.$id)),
          Permission.update(Role.user(appwriteUser.$id)),
          Permission.delete(Role.user(appwriteUser.$id)),
        ],
      );

      return appwriteUser;
    } on AppwriteException catch (e) {
      throw _handleError(e);
    } catch (e) {
      rethrow;
    }
  }

  /// Email veya Kullanıcı Adı ile giriş yap
  Future<models.Session> login({
    required String identifier,
    required String password,
  }) async {
    try {
      String email = identifier;

      // Eğer input bir email değilse, username olarak kabul et ve email'i bul
      final isEmail = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(identifier);

      if (!isEmail) {
        final userList = await _databases.listDocuments(
          databaseId: databaseId,
          collectionId: usersCollectionId,
          queries: [
            Query.equal('username', identifier),
            Query.limit(1),
          ],
        );

        if (userList.documents.isEmpty) {
          throw Exception('Bu kullanıcı adı ile kayıtlı kullanıcı bulunamadı.');
        }

        email = userList.documents.first.data['email'];
      }

      final session = await _account.createEmailPasswordSession(
        email: email,
        password: password,
      );
      return session;
    } on AppwriteException catch (e) {
      throw _handleError(e);
    } catch (e) {
      throw Exception('Giriş işlemi başarısız: ${e.toString()}');
    }
  }

  /// Çıkış yap
  Future<void> logout() async {
    try {
      // Mevcut oturumu sonlandır
      await _account.deleteSession(sessionId: 'current');
    } on AppwriteException catch (e) {
      throw _handleError(e);
    } catch (e) {
      throw Exception('Çıkış işlemi başarısız: ${e.toString()}');
    }
  }

  /// Şifre değiştir
  Future<models.User> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      return await _account.updatePassword(
        password: newPassword,
        oldPassword: oldPassword,
      );
    } on AppwriteException catch (e) {
      throw _handleError(e);
    } catch (e) {
      throw Exception('Şifre değiştirme işlemi başarısız: ${e.toString()}');
    }
  }

  /// Mevcut kullanıcıyı al
  Future<models.User?> getCurrentUser() async {
    try {
      return await _account.get();
    } on AppwriteException catch (e) {
      if (e.code == 401) {
        return null;
      }
      throw _handleError(e);
    } catch (e) {
      return null;
    }
  }

  /// Oturum kontrolü
  Future<bool> isLoggedIn() async {
    try {
      final user = await getCurrentUser();
      return user != null;
    } catch (e) {
      return false;
    }
  }

  /// Profil fotoğrafını güncelle
  /// [image] parametresi artık InputFile tipinde
  Future<void> updateProfileImage(String userId, InputFile image) async {
    try {
      // 1. Görseli Storage'a yükle
      final file = await _storage.createFile(
        bucketId: AppwriteConfig.storageBucketId,
        fileId: ID.unique(),
        file: image,
      );

      // 2. Kullanıcı dokümanını güncelle (Sadece ID)
      await _databases.updateDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: userId,
        data: {
          'photoId': file.$id, // 🟢 Şemaya uygun alan
        },
      );
    } on AppwriteException catch (e) {
      throw _handleError(e);
    }
  }

  /// 📤 Profil fotoğrafını yükle ve ID döndür
  Future<String> uploadProfilePhotoFile(InputFile image) async {
    try {
      final file = await _storage.createFile(
        bucketId: AppwriteConfig.storageBucketId,
        fileId: ID.unique(),
        file: image,
      );
      return file.$id;
    } on AppwriteException catch (e) {
      throw _handleError(e);
    }
  }

  /// 🆕 Yeni profil versiyonu oluştur (Append-Only)
  Future<void> createProfileVersion({
    required String userId,
    required Map<String, dynamic> oldProfileData,
    String? newDisplayName,
    String? newBio,
    String? newPhotoId,
    String? newUniversity,
    String? newFaculty,
    String? newDepartment,
    String? newUsername,
    String? newUsernameLastChangedAt,
  }) async {
    try {
      // Eski verileri kopyala
      final Map<String, dynamic> newData = Map.from(oldProfileData);
      
      // Sistem alanlarını temizle (Appwrite otomatik ekler)
      newData.remove('\$id');
      newData.remove('\$createdAt');
      newData.remove('\$updatedAt');
      newData.remove('\$permissions');
      newData.remove('\$collectionId');
      newData.remove('\$databaseId');

      // Yeni değerleri ata (null değilse)
      if (newDisplayName != null) newData['displayName'] = newDisplayName;
      if (newBio != null) newData['bio'] = newBio;
      if (newPhotoId != null) newData['photoId'] = newPhotoId;
      if (newUniversity != null) newData['university'] = newUniversity;
      if (newFaculty != null) newData['faculty'] = newFaculty;
      if (newDepartment != null) newData['department'] = newDepartment;
      if (newUsername != null) newData['username'] = newUsername;
      if (newUsernameLastChangedAt != null) newData['usernameLastChangedAt'] = newUsernameLastChangedAt;

      // Yeni doküman oluştur
      await _databases.createDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: ID.unique(),
        data: newData,
        permissions: [
          Permission.read(Role.user(userId)),
          Permission.update(Role.user(userId)),
          Permission.delete(Role.user(userId)),
        ],
      );
    } on AppwriteException catch (e) {
      throw _handleError(e);
    }
  }

  /// 🔒 Gizlilik Ayarını Güncelle
  Future<void> updatePrivacy(String userId, bool isPrivate) async {
    try {
      // Append-Only mimarisi nedeniyle en son oluşturulan profili bulup güncellemeliyiz
      final res = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        queries: [
          Query.equal('userId', userId),
          Query.orderDesc('\$createdAt'),
          Query.limit(1),
        ],
      );

      final targetDocId = res.documents.isNotEmpty ? res.documents.first.$id : userId;

      await _databases.updateDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: targetDocId,
        data: {'isPrivate': isPrivate},
      );
    } on AppwriteException catch (e) {
      throw _handleError(e);
    }
  }

  /// 🔄 Kullanıcı Adı Güncelle (30 Gün Kuralı ile)
  Future<void> updateUsername(String userId, String newUsername) async {
    try {
      // 1. Mevcut kullanıcı verisini çek (Tarih kontrolü için)
      final userDoc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: userId,
      );

      final lastChangedStr = userDoc.data['usernameLastChangedAt'] as String?;
      if (lastChangedStr != null) {
        final lastChanged = DateTime.parse(lastChangedStr);
        final difference = DateTime.now().difference(lastChanged).inDays;
        if (difference < 30) {
          throw Exception('Kullanıcı adını 30 günde bir değiştirebilirsin. ${30 - difference} gün daha beklemen gerekiyor.');
        }
      }

      // 2. Müsaitlik Kontrolü
      final isAvailable = await checkUsernameAvailability(newUsername);
      if (!isAvailable) throw Exception('Bu kullanıcı adı zaten kullanımda.');

      // 3. Güncelleme
      await _databases.updateDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: userId,
        data: {
          'username': newUsername,
          'usernameLastChangedAt': DateTime.now().toIso8601String(),
        },
      );
    } on AppwriteException catch (e) {
      throw _handleError(e);
    }
  }

  ///  Kullanıcı adı müsait mi kontrolü
  /// True dönerse müsait, False dönerse dolu
  Future<bool> checkUsernameAvailability(String username) async {
    try {
      final res = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        queries: [
          Query.equal('username', username),
          Query.limit(1),
        ],
      );
      return res.documents.isEmpty;
    } catch (e) {
      // Hata durumunda (örn: ağ hatası) false dönmek yerine hatayı fırlatabiliriz
      // ama şimdilik güvenli tarafta kalıp false (kullanılamaz) diyelim veya true varsayalım.
      // Genelde bağlantı hatası varsa işlem yapmamak daha iyidir.
      print('Username check error: $e');
      return false; 
    }
  }

  /// 🔔 Cihazın FCM Token'ını Appwrite'a kaydeder (Push Bildirimleri için)
  Future<String> registerPushToken() async {
    try {
      // 1. Token al
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        return '❌ HATA: FCM Token alınamadı (null).';
      }

      // 2. Appwrite'a kaydet
      // Not: Client SDK'da listPushTargets olmadığı için direkt eklemeyi deniyoruz.
      const String providerId = 'fcm'; 
      await _account.createPushTarget(
        targetId: ID.unique(),
        identifier: token,
        providerId: providerId,
      );
      return '✅ BAŞARILI: Cihaz bildirime açıldı.\nToken: ${token.substring(0, 6)}...';
    } catch (e) {
      // Hata mesajını döndür (Ekranda görmek için)
      return '⚠️ Target Kayıt Hatası: $e';
    }
  }

  /// Appwrite hatalarını kullanıcı dostu mesajlara çevirir
  String _handleError(AppwriteException e) {
    switch (e.code) {
      case 401:
        return 'E-posta veya şifre hatalı';
      case 409:
        return 'Bu e-posta adresi zaten kullanılıyor';
      case 429:
        return 'Çok fazla istek gönderdiniz. Lütfen bir süre bekleyin';
      default:
        return e.message ?? 'Bir hata oluştu';
    }
  }
}