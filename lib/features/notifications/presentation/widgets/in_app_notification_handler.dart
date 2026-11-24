import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/config/appwrite_config.dart';
import '../../../../services/appwrite_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../messages/data/message_providers.dart';

/// Uygulama içi bildirimleri (Snackbar) yöneten Wrapper Widget
class InAppNotificationHandler extends ConsumerStatefulWidget {
  final Widget child;
  const InAppNotificationHandler({super.key, required this.child});

  @override
  ConsumerState<InAppNotificationHandler> createState() => _InAppNotificationHandlerState();
}

class _InAppNotificationHandlerState extends ConsumerState<InAppNotificationHandler> {
  StreamSubscription? _messageSub;
  StreamSubscription? _notificationSub;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  void _startListening() {
    final realtime = AppwriteService.realtime;

    // 1. MESAJLARI DİNLE
    _messageSub = realtime.subscribe([
      'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.messagesCollectionId}.documents'
    ]).stream.listen((event) {
      if (event.events.any((e) => e.endsWith('.create'))) {
        final payload = event.payload;
        final currentUser = ref.read(currentUserProvider).value;
        
        // Bana gelen bir mesaj mı?
        if (currentUser != null && payload['receiverId'] == currentUser.$id) {
          // Kendi mesajım değilse
          if (payload['senderId'] != currentUser.$id) {
            // Şu an o sohbetin içinde miyim? (Basit kontrol)
            final String currentLocation = GoRouterState.of(context).uri.toString();
            final String chatId = payload['chatId'];
            
            // Eğer o sohbet sayfasında değilsem bildirim göster
            if (!currentLocation.contains(chatId)) {
              _showSnackbar(
                title: 'Yeni Mesaj',
                message: payload['messageType'] == 'text' ? payload['content'] : 'Medya gönderildi',
                onTap: () => context.push('/chat/$chatId', extra: 'Sohbet'),
                icon: Icons.mail_outline,
              );
              // Mesaj listesini yenile
              ref.invalidate(myChatsProvider);
            }
          }
        }
      }
    });

    // 2. DİĞER BİLDİRİMLERİ DİNLE (Beğeni, Yorum, Takip)
    _notificationSub = realtime.subscribe([
      'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.notificationsCollectionId}.documents'
    ]).stream.listen((event) {
      if (event.events.any((e) => e.endsWith('.create'))) {
        final payload = event.payload;
        final currentUser = ref.read(currentUserProvider).value;

        // Bana gelen bir bildirim mi?
        if (currentUser != null && payload['toUserId'] == currentUser.$id) {
          final type = payload['type'];
          final eventId = payload['eventId'];
          final fromUserId = payload['fromUserId'];

          _showSnackbar(
            title: 'Yeni Bildirim',
            message: payload['content'] ?? 'Yeni bir bildiriminiz var.',
            onTap: () {
              switch (type) {
                case 'like':
                case 'post_like':
                case 'comment':
                case 'comment_reply':
                case 'repost':
                case 'mention':
                  context.push('/post/$eventId');
                  break;
                case 'event':
                case 'event_application':
                case 'event_approved':
                case 'event_rejected':
                  context.push('/event/$eventId');
                  break;
                default:
                  // follow, vb. durumlar için
                  context.push('/profile/$fromUserId');
              }
            },
            icon: Icons.notifications_active_outlined,
          );
        }
      }
    });
  }

  void _showSnackbar({
    required String title,
    required String message,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        backgroundColor: Colors.grey[900],
        duration: const Duration(seconds: 4),
        content: InkWell(
          onTap: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            onTap();
          },
          child: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    Text(message, style: const TextStyle(color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _notificationSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
