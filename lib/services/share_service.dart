import 'package:appwrite/appwrite.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/appwrite_config.dart';
import 'appwrite_service.dart';

final shareServiceProvider = Provider((ref) => ShareService());

class ShareService {
  final Databases _databases = AppwriteService.databases;
  
  // Messages koleksiyon ID'si (Config dosyasında yoksa buraya tanımlıyoruz)
  static const String messagesCollectionId = 'messages';

  /// 📱 Sistem Paylaşımı (Share Plus)
  Future<void> shareSystem(String text) async {
    await Share.share(text);
  }

  /// 🟢 WhatsApp Paylaşımı
  Future<void> shareToWhatsApp(String text) async {
    final encodedText = Uri.encodeComponent(text);
    final appUrl = Uri.parse("whatsapp://send?text=$encodedText");
    final webUrl = Uri.parse("https://wa.me/?text=$encodedText");

    try {
      if (await canLaunchUrl(appUrl)) {
        await launchUrl(appUrl);
      } else {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      throw Exception('WhatsApp açılamadı.');
    }
  }

  /// 📸 Instagram DM (Link Kopyala + Uygulama Aç)
  Future<void> openInstagramDM(String text) async {
    // Önce linki kopyala
    await Clipboard.setData(ClipboardData(text: text));

    // Instagram DM kutusunu açmaya çalış
    final url = Uri.parse("instagram://direct-inbox");
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Instagram yüklü değil.');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 🔗 Link Kopyala
  Future<void> copyLink(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// 📩 Uygulama İçi Mesaj Olarak Gönder
  Future<void> sendPostAsMessage({
    required String senderId,
    required String receiverId,
    required String postId,
  }) async {
    try {
      await _databases.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: messagesCollectionId,
        documentId: ID.unique(),
        data: {
          'senderId': senderId,
          'receiverId': receiverId,
          'messageType': 'post',
          'postId': postId,
          'content': 'Bir gönderi paylaştı',
          'isRead': false,
        },
      );
    } catch (e) {
      throw Exception('Mesaj gönderilemedi: $e');
    }
  }
}