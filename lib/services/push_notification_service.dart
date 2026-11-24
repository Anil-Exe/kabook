import 'dart:io';
import 'package:appwrite/appwrite.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'appwrite_service.dart';

final pushNotificationServiceProvider = Provider((ref) => PushNotificationService());

class PushNotificationService {
  final Account _account = AppwriteService.account;

  /// 📲 Cihaz Token'ını Appwrite'a Kaydet (Target Oluştur)
  Future<void> registerDeviceToken() async {
    try {
      // 1. İzin İste
      NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        debugPrint('❌ Bildirim izni verilmedi.');
        return;
      }

      // 2. FCM Token'ı Al
      String? fcmToken = await FirebaseMessaging.instance.getToken();
      
      if (fcmToken == null) {
        debugPrint('❌ FCM Token alınamadı.');
        return;
      }

      debugPrint('🔥 FCM Token: $fcmToken');

      // 3. Kullanıcının Mevcut Target'larını Kontrol Et
      // (Client SDK'da listTargets olmadığı için Prefs kullanıyoruz)
      try {
        final prefs = await _account.getPrefs();
        if (prefs.data['fcmToken'] == fcmToken) {
          debugPrint('✅ Bu cihaz zaten Appwrite Target olarak kayıtlı (Prefs).');
          return;
        }
      } catch (_) {
        // Prefs okunamadıysa devam et
      }

      // 4. Yeni Target Oluştur
      final target = await _account.createPushTarget(
        targetId: ID.unique(),
        identifier: fcmToken, // FCM Token buraya
        providerId: '69a4c0d800369c9e70fd', // ✅ GÜNCELLENDİ: FCM Provider ID
      );
      debugPrint('🎉 Yeni Push Target başarıyla oluşturuldu!');

      // 5. Prefs Güncelle
      try {
        final prefs = await _account.getPrefs();
        final data = Map<String, dynamic>.from(prefs.data);
        data['fcmToken'] = fcmToken;
        data['fcmTargetId'] = target.$id;
        await _account.updatePrefs(prefs: data);
      } catch (_) {}

    } catch (e) {
      debugPrint('❌ Token kayıt hatası: $e');
      // Eğer kullanıcı giriş yapmamışsa bu hata normaldir (AppwriteException: User (role: member) missing scope (account))
    }
  }
}
