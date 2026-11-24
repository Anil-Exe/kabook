import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/theme/app_theme.dart';
import '../../../../services/image_upload_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../../data/message_providers.dart';

class MessageRequestsPage extends ConsumerWidget {
  const MessageRequestsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(messageRequestsProvider);
    final currentUser = ref.watch(currentUserProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesaj İstekleri'),
      ),
      body: Column(
        children: [
          // Bilgilendirme Kutusu
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.withOpacity(0.1),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tanımadığınız kişilerden gelen mesajlar burada görünür. Cevap verdiğinizde istek kabul edilir.',
                    style: TextStyle(color: Colors.grey[700], fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          
          // İstek Listesi
          Expanded(
            child: requestsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Hata: $e')),
              data: (chats) {
                if (chats.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mark_email_read_outlined, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('Bekleyen mesaj isteği yok', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: chats.length,
                  padding: const EdgeInsets.all(12),
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    final data = chat.data;
                    final lastMessage = data['lastMessage'] ?? '';
                    final lastMessageAt = DateTime.parse(data['lastMessageAt']);

                    // Karşı tarafı bul
                    final participants = List<String>.from(data['participantIds'] ?? []);
                    final otherUserId = participants.firstWhere(
                      (id) => id != currentUser?.$id,
                      orElse: () => '',
                    );

                    return Consumer(
                      builder: (context, ref, _) {
                        final userAsync = ref.watch(userProfileProvider(otherUserId));
                        
                        return userAsync.when(
                          data: (user) {
                            final name = user?['displayName'] ?? 'Kullanıcı';
                            final photoId = user?['photoId'] ?? user?['profileImageUrl'];
                            
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: Column(
                                children: [
                                  ListTile(
                                    contentPadding: const EdgeInsets.all(12),
                                    leading: CircleAvatar(
                                      radius: 24,
                                      backgroundImage: photoId != null 
                                          ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId)) 
                                          : null,
                                      child: photoId == null ? Text(name[0]) : null,
                                    ),
                                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text(
                                      lastMessage, 
                                      maxLines: 2, 
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.black87),
                                    ),
                                    trailing: Text(timeago.format(lastMessageAt, locale: 'tr'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    onTap: () {
                                      context.push('/chat/$otherUserId', extra: {'chatId': chat.$id, 'title': name});
                                    },
                                  ),
                                  const Divider(height: 1),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: TextButton.icon(
                                            onPressed: () async {
                                              // SİL / REDDET
                                              await ref.read(messageServiceProvider).deleteChat(chat.$id);
                                              ref.invalidate(messageRequestsProvider);
                                            },
                                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                            label: const Text('Sil', style: TextStyle(color: Colors.red)),
                                          ),
                                        ),
                                        Container(width: 1, height: 24, color: Colors.grey[300]),
                                        Expanded(
                                          child: TextButton.icon(
                                            onPressed: () async {
                                              // KABUL ET
                                              await ref.read(messageServiceProvider).acceptMessageRequest(chat.$id);
                                              ref.invalidate(messageRequestsProvider);
                                              ref.invalidate(myChatsProvider);
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İstek kabul edildi')));
                                              }
                                            },
                                            icon: const Icon(Icons.check_circle_outline, color: AppColors.primaryGreen, size: 20),
                                            label: const Text('Kabul Et', style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                          loading: () => const ListTile(leading: CircleAvatar(), title: Text('...')),
                          error: (_,__) => const SizedBox.shrink(),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}