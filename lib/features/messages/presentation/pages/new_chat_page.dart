import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../services/image_upload_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../follow/data/follow_service.dart';
import '../../data/message_providers.dart';
import 'create_group_page.dart';

class NewChatPage extends ConsumerWidget {
  const NewChatPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yeni Sohbet'),
      ),
      body: Column(
        children: [
          // Yeni Grup Oluştur Seçeneği
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primaryGreen.withOpacity(0.1),
              child: const Icon(Icons.group_add, color: AppColors.primaryGreen),
            ),
            title: const Text('Yeni Grup Oluştur', style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CreateGroupPage()),
              );
            },
          ),
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Kişiler', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
          ),
          
          // Kişi Listesi (Takip Edilenler)
          Expanded(
            child: currentUser == null 
              ? const SizedBox.shrink()
              : FutureBuilder(
                  future: ref.read(followServiceProvider).getFollowing(currentUser.$id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    
                    final users = snapshot.data ?? [];
                    if (users.isEmpty) {
                      return const Center(child: Text('Takip ettiğiniz kimse yok.'));
                    }

                    return ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final doc = users[index];
                        final targetUserId = doc.data['followingId'];

                        return Consumer(
                          builder: (context, ref, _) {
                            final userAsync = ref.watch(userProfileProvider(targetUserId));
                            
                            return userAsync.when(
                              data: (userData) {
                                if (userData == null) return const SizedBox.shrink();
                                
                                final name = userData['displayName'] ?? 'Kullanıcı';
                                final photoId = userData['photoId'] ?? userData['profileImageUrl'];

                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundImage: photoId != null 
                                      ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId)) 
                                      : null,
                                    child: photoId == null ? Text(name[0]) : null,
                                  ),
                                  title: Text(name),
                                  onTap: () async {
                                    // Birebir Sohbet Başlat
                                    final chatDoc = await ref.read(messageServiceProvider).getOrCreateDirectChat(
                                      currentUserId: currentUser.$id,
                                      targetUserId: targetUserId,
                                    );
                                    if (context.mounted) {
                                      context.push('/chat/${chatDoc.$id}', extra: name);
                                    }
                                  },
                                );
                              },
                              loading: () => const ListTile(title: Text('Yükleniyor...')),
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