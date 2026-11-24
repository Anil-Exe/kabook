import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;

import '../../../../core/theme/app_theme.dart';
import '../../../../services/image_upload_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../follow/data/follow_service.dart';
import '../../data/message_providers.dart';
import '../../../../services/appwrite_service.dart';
import '../../../../core/config/appwrite_config.dart';

class GroupInfoPage extends ConsumerWidget {
  final String chatId;

  const GroupInfoPage({super.key, required this.chatId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider).value;
    final chatsAsync = ref.watch(myChatsProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Grup Bilgisi'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Üyeler'),
            Tab(text: 'Medya'),
            Tab(text: 'Dosyalar'),
          ],
        ),
      ),
      body: chatsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (chats) {
          // İlgili sohbeti bul
          final chat = chats.firstWhere(
            (c) => c.$id == chatId,
            orElse: () => throw Exception('Grup bulunamadı'),
          );
          
          final data = chat.data;
          final groupName = data['groupName'] ?? 'Grup';
          final groupImageId = data['groupImageId'];
          final participantIds = List<String>.from(data['participantIds'] ?? []);
          final adminIds = List<String>.from(data['adminIds'] ?? []);
          
          final isMeAdmin = adminIds.contains(currentUser?.$id);

          return TabBarView(
            children: [
              // --- TAB 1: ÜYELER ---
              SingleChildScrollView(
                child: Column(
              children: [
                const SizedBox(height: 20),
                // --- GRUP RESMİ VE ADI ---
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.orange.shade100,
                  backgroundImage: groupImageId != null 
                      ? CachedNetworkImageProvider(MediaService.getFileUrl(groupImageId)) 
                      : null,
                  child: groupImageId == null 
                      ? const Icon(Icons.groups, size: 50, color: Colors.grey) 
                      : null,
                ),
                const SizedBox(height: 16),
                Text(
                  groupName,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${participantIds.length} üye',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 20),
                const Divider(),

                // --- KATILIMCILAR LİSTESİ ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Katılımcılar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      if (isMeAdmin)
                        TextButton.icon(
                          icon: const Icon(Icons.person_add, size: 18),
                          label: const Text('Üye Ekle'),
                          onPressed: () => _showAddMemberSheet(
                            context, 
                            ref, 
                            participantIds, 
                            chatId
                          ),
                        ),
                    ],
                  ),
                ),
                
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: participantIds.length,
                  itemBuilder: (context, index) {
                    final userId = participantIds[index];
                    final isAdmin = adminIds.contains(userId);
                    final isMe = userId == currentUser?.$id;

                    return Consumer(
                      builder: (context, ref, _) {
                        final userAsync = ref.watch(userProfileProvider(userId));
                        
                        return userAsync.when(
                          data: (user) {
                            final name = user?['displayName'] ?? 'Kullanıcı';
                            final photoId = user?['photoId'] ?? user?['profileImageUrl'];

                            return ListTile(
                              onTap: () => context.push('/profile/$userId'),
                              leading: CircleAvatar(
                                backgroundImage: photoId != null 
                                    ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId)) 
                                    : null,
                                child: photoId == null ? Text(name[0]) : null,
                              ),
                              title: Row(
                                children: [
                                  Text(isMe ? 'Siz' : name),
                                  if (isAdmin)
                                    Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryGreen.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: AppColors.primaryGreen, width: 0.5),
                                      ),
                                      child: const Text('Yönetici', style: TextStyle(fontSize: 10, color: AppColors.primaryGreen)),
                                    ),
                                ],
                              ),
                              trailing: (isMeAdmin && !isMe)
                                  ? PopupMenuButton<String>(
                                      onSelected: (value) async {
                                        if (value == 'remove') {
                                          await ref.read(messageServiceProvider).removeParticipant(
                                            chatId: chatId,
                                            adminId: currentUser!.$id,
                                            targetUserId: userId,
                                            targetUserName: name,
                                          );
                                        } else if (value == 'make_admin') {
                                          await ref.read(messageServiceProvider).toggleGroupAdmin(
                                            chatId: chatId,
                                            targetUserId: userId,
                                            targetUserName: name,
                                            makeAdmin: true,
                                          );
                                        } else if (value == 'remove_admin') {
                                          await ref.read(messageServiceProvider).toggleGroupAdmin(
                                            chatId: chatId,
                                            targetUserId: userId,
                                            targetUserName: name,
                                            makeAdmin: false,
                                          );
                                        }
                                        ref.invalidate(myChatsProvider);
                                      },
                                      itemBuilder: (context) => [
                                        if (!isAdmin)
                                          const PopupMenuItem(
                                            value: 'make_admin',
                                            child: Text('Yönetici Yap'),
                                          )
                                        else
                                          const PopupMenuItem(
                                            value: 'remove_admin',
                                            child: Text('Yöneticilikten Al'),
                                          ),
                                        const PopupMenuItem(
                                          value: 'remove',
                                          child: Text('Gruptan Çıkar', style: TextStyle(color: Colors.red)),
                                        ),
                                      ],
                                    )
                                  : null,
                            );
                          },
                          loading: () => const ListTile(title: Text('Yükleniyor...')),
                          error: (_,__) => const SizedBox.shrink(),
                        );
                      },
                    );
                  },
                ),

                const Divider(),
                
                // --- GRUPTAN ÇIK BUTONU ---
                ListTile(
                  leading: const Icon(Icons.exit_to_app, color: Colors.red),
                  title: const Text('Gruptan Çık', style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Gruptan Çık'),
                        content: const Text('Bu gruptan ayrılmak istediğinize emin misiniz?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('İptal')),
                          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ayrıl', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );

                    if (confirm == true && currentUser != null) {
                      await ref.read(messageServiceProvider).leaveGroup(
                        chatId: chatId,
                        userId: currentUser.$id,
                        userName: currentUser.name,
                      );
                      if (context.mounted) context.go('/messages');
                    }
                  },
                ),
                const SizedBox(height: 40),
              ],
            ),
              ),

              // --- TAB 2: MEDYA (Resimler/Videolar) ---
              _GroupMediaTab(chatId: chatId, types: const ['image', 'video']),

              // --- TAB 3: DOSYALAR (Belgeler/Linkler) ---
              _GroupMediaTab(chatId: chatId, types: const ['file', 'link']),
            ],
          );
        },
      ),
    ),
    );
  }

  void _showAddMemberSheet(BuildContext context, WidgetRef ref, List<String> currentMembers, String chatId) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final currentUser = ref.read(currentUserProvider).value;
        if (currentUser == null) return const SizedBox.shrink();

        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Üye Ekle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            Expanded(
              child: FutureBuilder(
                future: ref.read(followServiceProvider).getFollowing(currentUser.$id),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  
                  final users = snapshot.data ?? [];
                  // Zaten grupta olanları filtrele
                  final availableUsers = users.where((doc) => !currentMembers.contains(doc.data['followingId'])).toList();

                  if (availableUsers.isEmpty) {
                    return const Center(child: Text('Eklenebilecek kimse yok.'));
                  }

                  return ListView.builder(
                    itemCount: availableUsers.length,
                    itemBuilder: (context, index) {
                      final targetUserId = availableUsers[index].data['followingId'];
                      
                      return Consumer(
                        builder: (context, ref, _) {
                          final userAsync = ref.watch(userProfileProvider(targetUserId));
                          return userAsync.when(
                            data: (user) => ListTile(
                              leading: CircleAvatar(
                                backgroundImage: user?['photoId'] != null ? CachedNetworkImageProvider(MediaService.getFileUrl(user!['photoId'])) : null,
                              ),
                              title: Text(user?['displayName'] ?? 'Kullanıcı'),
                              trailing: const Icon(Icons.add_circle_outline, color: AppColors.primaryGreen),
                              onTap: () async {
                                Navigator.pop(context);
                                await ref.read(messageServiceProvider).addParticipant(chatId: chatId, newUserId: targetUserId, newUserName: user?['displayName'] ?? 'Kullanıcı');
                                ref.invalidate(myChatsProvider);
                              },
                            ),
                            loading: () => const SizedBox.shrink(),
                            error: (_,__) => const SizedBox.shrink(),
                          );
                        }
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GroupMediaTab extends StatelessWidget {
  final String chatId;
  final List<String> types;

  const _GroupMediaTab({required this.chatId, required this.types});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<models.DocumentList>(
      future: AppwriteService.databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.messagesCollectionId,
        queries: [
          Query.equal('chatId', chatId),
          Query.equal('messageType', types),
          Query.orderDesc('\$createdAt'),
        ],
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.documents.isEmpty) {
          return const Center(child: Text('Öğe bulunamadı.'));
        }

        final docs = snapshot.data!.documents;

        if (types.contains('image')) {
          // Grid Görünümü (Medya)
          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final fileId = docs[index].data['fileId'];
              return CachedNetworkImage(
                imageUrl: AppwriteService.getFilePreviewUrl(fileId),
                fit: BoxFit.cover,
              );
            },
          );
        } else {
          // Liste Görünümü (Dosyalar)
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data;
              return ListTile(
                leading: const Icon(Icons.insert_drive_file),
                title: Text(data['content'] ?? 'Dosya'),
                subtitle: Text(data['\$createdAt'].toString().substring(0, 10)),
              );
            },
          );
        }
      },
    );
  }
}