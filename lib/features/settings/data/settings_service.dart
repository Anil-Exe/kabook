import 'package:appwrite/appwrite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/appwrite_service.dart';

final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService();
});

class SettingsService {
  final Account _account = AppwriteService.account;

  /// 🚪 ÇIKIŞ YAP
  Future<void> logout() async {
    try {
      await _account.deleteSession(sessionId: 'current');
    } catch (e) {
      throw Exception('Çıkış yapılamadı: $e');
    }
  }

  /// 🔐 ŞİFRE DEĞİŞTİR
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      await _account.updatePassword(
        password: newPassword,
        oldPassword: oldPassword,
      );
    } catch (e) {
      throw Exception('Şifre değiştirilemedi: $e');
    }
  }
}
