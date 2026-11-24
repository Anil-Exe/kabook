// lib/features/auth/data/auth_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/appwrite_service.dart';
import '../../../core/config/appwrite_config.dart';

/// Auth Service Provider
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

/// Database Service Provider
final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return DatabaseService();
});

/// Mevcut oturumdaki kullanıcı (Appwrite Account'tan)
final currentUserProvider = FutureProvider<models.User?>((ref) async {
  final authService = ref.watch(authServiceProvider);
  try {
    return await authService.getCurrentUser();
  } catch (e) {
    return null; // Oturum yoksa null döner
  }
});

/// Kullanıcı oturum açmış mı?
final isLoggedInProvider = FutureProvider<bool>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  return user != null;
});

/// 👤 KULLANICI PROFİLİ (EN GÜNCEL VERSİYON)
/// Append-Only mimarisinde en son oluşturulan kaydı getirir.
final userProvider = FutureProvider.family<models.Document, String>((ref, userId) async {
  final databases = AppwriteService.databases;
  final res = await databases.listDocuments(
    databaseId: AppwriteConfig.databaseId,
    collectionId: AppwriteConfig.usersCollectionId,
    queries: [
      Query.equal('userId', userId),
      Query.orderDesc('\$createdAt'), // En son oluşturulanı al
      Query.limit(1),
    ],
  );

  if (res.documents.isEmpty) throw Exception('Kullanıcı profili bulunamadı');
  return res.documents.first;
});

/// Belirli bir kullanıcıya ait profil verileri (users collection'dan)
/// Kullanım: ref.watch(userProfileProvider('user_id'))
final userProfileProvider = FutureProvider.family<Map<String, dynamic>?, String>((ref, userId) async {
  try {
    // 🟢 DÜZELTME: userProvider zaten en güncel veriyi (Query.orderDesc) çekiyor.
    // Eski ID bazlı çekim yerine bunu kullanıyoruz.
    final doc = await ref.watch(userProvider(userId).future);
    return doc.data;
  } catch (e) {
    // Hata durumunda null döner, UI'da "yüklenemedi" gösterilebilir
    return null;
  }
});

/// Mevcut kullanıcının profil verileri (kendi profili)
/// Kullanım: ref.watch(currentUserProfileProvider)
final currentUserProfileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  if (currentUser == null) return null;

  // 🟢 DÜZELTME: .value yerine .future ile verinin gelmesini bekliyoruz
  return await ref.watch(userProfileProvider(currentUser.$id).future);
});