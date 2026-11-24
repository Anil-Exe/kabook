import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

final shareServiceProvider = Provider((ref) => ShareService());

class ShareService {
  Future<void> shareToWhatsApp(String text) async {
    final url = Uri.parse('whatsapp://send?text=${Uri.encodeComponent(text)}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      await shareSystem(text);
    }
  }

  Future<void> openInstagramDM(String text) async {
    // Instagram'ı açmayı dener, metni panoya kopyalar
    final url = Uri.parse('instagram://');
    if (await canLaunchUrl(url)) {
      await Clipboard.setData(ClipboardData(text: text));
      await launchUrl(url);
    } else {
      await shareSystem(text);
    }
  }

  Future<void> copyLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
  }

  Future<void> shareSystem(String text) async {
    await Share.share(text);
  }
}