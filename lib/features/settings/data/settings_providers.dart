import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appwrite/appwrite.dart';

import '../../../services/appwrite_service.dart';

final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService();
});

class SettingsService {
  final Account _account = AppwriteService.account;

  /// 🚪 ÇIKIŞ YAP
  Future<void> logout() async {
    await _account.deleteSession(sessionId: 'current');
  }

  /// 🔐 ŞİFRE DEĞİŞTİR
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _account.updatePassword(
      password: newPassword,
      oldPassword: oldPassword,
    );
  }
}
