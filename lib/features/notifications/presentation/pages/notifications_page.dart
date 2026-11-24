import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../services/image_upload_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../../data/notification_providers.dart';
import '../../data/notification_model.dart';
import '../../data/notification_service.dart';
import '../widgets/follow_requests_section.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirimler'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Tümünü Okundu İşaretle',
            onPressed: () async {
              final notifications = notificationsAsync.valueOrNull;
              if (notifications == null) return;

              final unreadIds = notifications
                  .where((n) => !n.isRead)
                  .map((n) => n.id)
                  .toList();

              if (unreadIds.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Okunmamış bildirim yok')),
                );
                return;
              }

              await ref.read(notificationServiceProvider).markAllAsRead(unreadIds);
              
              // Sayacı ve listeyi güncelle
              ref.read(unreadNotificationCountProvider.notifier).refreshCount();
              ref.invalidate(notificationsProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
           ref.invalidate(notificationsProvider);
           // Okunmamış sayısını da yenile
           ref.read(unreadNotificationCountProvider.notifier).refreshCount();
        },
        child: ListView(
          children: [
            // 1. Takip İstekleri Bölümü (En üstte sabit)
            const FollowRequestsSection(),

            // 2. Bildirim Listesi
            notificationsAsync.when(
              data: (notifications) {
                if (notifications.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('Henüz bildirim yok', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: notifications.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final notification = notifications[index];
                    return Dismissible(
                      key: Key(notification.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (direction) {
                        // Bildirimi sil
                        ref.read(notificationServiceProvider).deleteNotification(notification.id);

                        // Geri Alma (Undo) SnackBar'ı
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Bildirim silindi'),
                            action: SnackBarAction(
                              label: 'Geri Al',
                              onPressed: () {
                                ref.read(notificationServiceProvider).createNotification(
                                  toUserId: notification.toUserId,
                                  fromUserId: notification.fromUserId,
                                  type: notification.type,
                                  content: notification.content,
                                  eventId: notification.eventId,
                                  status: notification.status,
                                  isRead: notification.isRead,
                                );
                              },
                            ),
                          ),
                        );
                      },
                      child: _NotificationTile(notification: notification),
                    );
                  },
                );
              },
              loading: () => const Center(child: Padding(
                padding: EdgeInsets.all(20.0),
                child: CircularProgressIndicator(),
              )),
              error: (e, _) => Center(child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Text('Hata: $e'),
              )),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  final NotificationModel notification;

  const _NotificationTile({required this.notification});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Bildirimi gönderen kullanıcının bilgilerini çek
    final userAsync = ref.watch(userProvider(notification.fromUserId));

    return InkWell(
      onTap: () async {
        // 1. Okundu olarak işaretle
        if (!notification.isRead) {
          await ref.read(unreadNotificationCountProvider.notifier).markAsRead(notification.id);
        }

        if (!context.mounted) return;

        // 2. Bildirim türüne göre ilgili sayfaya yönlendir
        final type = notification.type;
        final eventId = notification.eventId; // Çoğu bildirimde ilgili içeriğin ID'sini tutar
        final fromUserId = notification.fromUserId;

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
            // follow, follow_accepted, story_like veya bilinmeyenler için profile git
            context.push('/profile/$fromUserId');
        }
      },
      child: Container(
        color: notification.isRead ? null : AppColors.brandGreen.withOpacity(0.05),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            userAsync.when(
              data: (userDoc) {
                final data = userDoc.data;
                final photoId = data['photoId'];
                return CircleAvatar(
                  radius: 24,
                  backgroundImage: photoId != null
                      ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId))
                      : null,
                  child: photoId == null ? const Icon(Icons.person) : null,
                );
              },
              loading: () => const CircleAvatar(radius: 24, child: Icon(Icons.person, color: Colors.grey)),
              error: (_, __) => const CircleAvatar(radius: 24, child: Icon(Icons.error)),
            ),
            const SizedBox(width: 16),
            
            // İçerik
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.content,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: notification.isRead ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeago.format(notification.createdAt, locale: 'tr'),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),

            // İkon (Türe göre)
            _buildNotificationIcon(notification.type),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationIcon(String type) {
    IconData icon;
    Color color;

    switch (type) {
      case 'post_like':
        icon = Icons.favorite;
        color = Colors.red;
        break;
      case 'story_like':
        icon = Icons.favorite_border;
        color = Colors.purpleAccent;
        break;
      case 'comment':
      case 'comment_reply':
        icon = Icons.chat_bubble;
        color = Colors.blue;
        break;
      case 'follow':
      case 'follow_accepted':
        icon = Icons.person_add;
        color = AppColors.brandGreen;
        break;
      case 'repost':
        icon = Icons.repeat;
        color = Colors.green;
        break;
      case 'event_application':
      case 'event_approved':
      case 'event_rejected':
        icon = Icons.event;
        color = Colors.orange;
        break;
      default:
        icon = Icons.notifications;
        color = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(left: 8),
      child: Icon(icon, size: 20, color: color),
    );
  }
}