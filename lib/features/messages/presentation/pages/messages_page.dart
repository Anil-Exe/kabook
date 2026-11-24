import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:appwrite/models.dart' as models;

import '../../../../core/theme/app_theme.dart';
import '../../../../services/image_upload_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../../data/message_providers.dart';
import '../../../block/data/block_service.dart';
import 'chat_page.dart';
import 'message_requests_page.dart';
import 'new_chat_search_page.dart';
import 'create_group_page.dart';

class MessagesPage extends ConsumerWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider).value;
    final chatsAsync = ref.watch(myChatsProvider);
    final requestsAsync = ref.watch(messageRequestsProvider); // İstek sayısını dinle

    // 🔥 REALTIME LİSTE DÜZELTME: Stream'den veri gelince listeyi yenile
    ref.listen(myChatsRealtimeProvider, (previous, next) {
      // Sadece yeni veri geldiğinde yenile (Loading/Error durumlarında değil)
      if (next.hasValue) {
        ref.invalidate(myChatsProvider);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesajlar'),
        actions: [
          // 📩 İSTEKLER BUTONU
          requestsAsync.when(
            data: (requests) {
              return TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MessageRequestsPage()),
                  );
                },
                child: Row(
                  children: [
                    const Text('İstekler', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    if (requests.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text('${requests.length}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          // 👥 GRUP OLUŞTUR BUTONU
          IconButton(
            icon: const Icon(Icons.group_add_outlined),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGroupPage()));
            },
          ),
          // ➕ YENİ SOHBET BUTONU
          IconButton(
            icon: const Icon(Icons.add_comment_outlined), // İkon değişti
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NewChatSearchPage()),
              );
            },
          ),
        ],
      ),
      body: chatsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, stack) => Center(child: Text('Hata: $e')),
        data: (chats) {
          if (chats.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Henüz hiç sohbetiniz yok.', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.separated(
            itemCount: chats.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final chat = chats[index];
              final data = chat.data;
              final type = data['type'];
              final lastMessage = data['lastMessage'] ?? '';
              final lastMessageAt = data['lastMessageAt'] != null 
                  ? DateTime.parse(data['lastMessageAt']) 
                  : null;

              // Sohbetin Adını ve Resmini Belirle
              String title = 'Sohbet';
              String? imageId;
              bool isGroup = type == 'group';

              if (isGroup) {
                title = data['groupName'] ?? 'Grup';
                imageId = data['groupImageId'];
              } else {
                // Birebir sohbetse karşı tarafı bul
                final participants = List<String>.from(data['participantIds'] ?? []);
                final otherUserId = participants.firstWhere(
                  (id) => id != currentUser?.$id,
                  orElse: () => '',
                );

                // Karşı kullanıcının bilgisini çek (Async işlem UI içinde FutureBuilder ile)
                return Consumer(
                  builder: (context, ref, _) {
                    final otherUserAsync = ref.watch(userProfileProvider(otherUserId));
                    
                    return otherUserAsync.when(
                      data: (userData) {
                        final name = userData?['displayName'] ?? 'Kullanıcı';
                        final photo = userData?['photoId'] ?? userData?['profileImageUrl'];
                        
                        return _buildChatTile(
                          context, 
                          ref,
                          currentUser,
                          chat.$id, 
                          name, 
                          photo, 
                          lastMessage, 
                          lastMessageAt,
                          isGroup: false,
                          otherUserId: otherUserId,
                        );
                      },
                      loading: () => const ListTile(title: Text('Yükleniyor...')),
                      error: (_,__) => const SizedBox.shrink(),
                    );
                  },
                );
              }
              
              // 🗑️ SOLA KAYDIRARAK SİLME (Dismissible)
              return Dismissible(
                key: Key(chat.$id),
                direction: DismissDirection.endToStart, // Sağdan sola kaydırma
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Icon(isGroup ? Icons.exit_to_app : Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (direction) async {
                  return await showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(isGroup ? 'Gruptan Ayrıl' : 'Sohbeti Sil'),
                      content: Text(isGroup 
                          ? 'Bu gruptan ayrılmak istediğinize emin misiniz?' 
                          : 'Bu sohbeti silmek istediğinize emin misiniz?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true), 
                          child: Text(isGroup ? 'Ayrıl' : 'Sil', style: const TextStyle(color: Colors.red))
                        ),
                      ],
                    ),
                  );
                },
                onDismissed: (direction) async {
                  if (isGroup) {
                    // Gruptan Ayrıl
                    await ref.read(messageServiceProvider).leaveGroup(
                      chatId: chat.$id,
                      userId: currentUser!.$id,
                      userName: currentUser.name,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gruptan ayrıldınız')));
                  } else {
                    // Sohbeti Sil
                    await ref.read(messageServiceProvider).deleteChat(chat.$id);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sohbet silindi')));
                  }
                  // Listeyi yenile (Dismissible UI'dan kaldırır ama veriyi de tazeleyelim)
                  ref.invalidate(myChatsProvider);
                },
                child: _buildChatTile(
                  context, ref, currentUser, chat.$id, title, imageId, lastMessage, lastMessageAt,
                  isGroup: true,
                  otherUserId: null,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildChatTile(
    BuildContext context,
    WidgetRef ref,
    models.User? currentUser,
    String chatId,
    String title,
    String? photoId,
    String lastMessage,
    DateTime? date, {
    required bool isGroup,
    String? otherUserId,
  }) {
    return ListTile(
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: isGroup ? Colors.orange.shade100 : Colors.grey.shade200,
        backgroundImage: photoId != null 
            ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId)) 
            : null,
        child: photoId == null 
            ? Icon(isGroup ? Icons.groups : Icons.person, color: Colors.grey) 
            : null,
      ),
      title: Text(
        title, 
        style: const TextStyle(fontWeight: FontWeight.bold),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        lastMessage, 
        maxLines: 1, 
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.grey[600]),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (date != null)
            Text(
              timeago.format(date, locale: 'tr'),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.grey),
            onSelected: (value) async {
              if (value == 'delete') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text(isGroup ? 'Gruptan Ayrıl' : 'Sohbeti Sil'),
                    content: Text(isGroup ? 'Bu gruptan ayrılmak istediğinize emin misiniz?' : 'Bu sohbeti silmek istediğinize emin misiniz?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('İptal')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: Text(isGroup ? 'Ayrıl' : 'Sil', style: const TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirm == true) {
                  if (isGroup) {
                    await ref.read(messageServiceProvider).leaveGroup(chatId: chatId, userId: currentUser!.$id, userName: currentUser.name);
                  } else {
                    await ref.read(messageServiceProvider).deleteChat(chatId);
                  }
                  ref.invalidate(myChatsProvider);
                }
              } else if (value == 'block' && otherUserId != null) {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Kullanıcıyı Engelle'),
                    content: const Text('Bu kullanıcıyı engellemek istediğine emin misin?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('İptal')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Engelle', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirm == true) {
                  await ref.read(blockServiceProvider).blockUser(currentUserId: currentUser!.$id, targetUserId: otherUserId);
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kullanıcı engellendi.')));
                }
              }
            },
            itemBuilder: (context) => [
              if (!isGroup) const PopupMenuItem(value: 'block', child: Text('Engelle', style: TextStyle(color: Colors.red))),
              PopupMenuItem(value: 'delete', child: Text(isGroup ? 'Gruptan Ayrıl' : 'Sohbeti Sil', style: const TextStyle(color: Colors.red))),
            ],
          ),
        ],
      ),
      onTap: () {
        // ChatPage'e git (chatId ile)
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatPage(chatId: chatId, chatTitle: title),
          ),
        );
      },
    );
  }
}
