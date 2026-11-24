import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../services/image_upload_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../block/data/block_service.dart';
import 'chat_media_page.dart';

class ChatInfoPage extends ConsumerStatefulWidget {
  final String chatId;
  final String otherUserId;

  const ChatInfoPage({
    super.key,
    required this.chatId,
    required this.otherUserId,
  });

  @override
  ConsumerState<ChatInfoPage> createState() => _ChatInfoPageState();
}

class _ChatInfoPageState extends ConsumerState<ChatInfoPage> {
  bool _isMuted = false; // Mock data (Backend'de mute özelliği varsa oradan çekilmeli)

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider).value;
    final otherUserAsync = ref.watch(userProfileProvider(widget.otherUserId));
    
    // Engelleme durumu: [BenEngelledimMi, OEngellediMi]
    final blockStatusAsync = ref.watch(blockStatusProvider('${currentUser?.$id}|${widget.otherUserId}'));

    return Scaffold(
      appBar: AppBar(title: const Text('Kişi Bilgisi')),
      body: otherUserAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (user) {
          if (user == null) return const Center(child: Text('Kullanıcı bulunamadı'));

          final name = user['displayName'] ?? 'Kullanıcı';
          final username = user['username'] ?? '';
          final photoId = user['photoId'] ?? user['profileImageUrl'];
          final bio = user['bio'] ?? '';

          return SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 20),
                // --- PROFİL FOTOĞRAFI ---
                GestureDetector(
                  onTap: () => context.push('/profile/${widget.otherUserId}'),
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: photoId != null 
                        ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId)) 
                        : null,
                    child: photoId == null 
                        ? const Icon(Icons.person, size: 60, color: Colors.grey) 
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Text(
                  '@$username',
                  style: const TextStyle(color: Colors.grey, fontSize: 16),
                ),
                if (bio.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(bio, textAlign: TextAlign.center),
                  ),
                
                const SizedBox(height: 20),
                const Divider(),

                // --- MEDYA ---
                ListTile(
                  leading: const Icon(Icons.perm_media_outlined, color: AppColors.primaryGreen),
                  title: const Text('Medya, Bağlantılar ve Belgeler'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    context.push('/chat-media/${widget.chatId}');
                  },
                ),
                const Divider(),

                // --- SESSİZE AL ---
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_off_outlined),
                  title: const Text('Bildirimleri Sessize Al'),
                  value: _isMuted,
                  onChanged: (val) {
                    setState(() => _isMuted = val);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(val ? 'Sohbet sessize alındı' : 'Sohbet sesi açıldı')),
                    );
                  },
                ),
                const Divider(),

                // --- ENGELLE ---
                blockStatusAsync.when(
                  data: (status) {
                    final isBlockedByMe = status[0];
                    
                    return ListTile(
                      leading: const Icon(Icons.block, color: Colors.red),
                      title: Text(
                        isBlockedByMe ? 'Engeli Kaldır' : 'Engelle',
                        style: const TextStyle(color: Colors.red),
                      ),
                      onTap: () async {
                        if (currentUser == null) return;

                        if (isBlockedByMe) {
                          // Engeli Kaldır
                          await ref.read(blockServiceProvider).unblockUser(
                            currentUserId: currentUser.$id,
                            targetUserId: widget.otherUserId,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Engel kaldırıldı')));
                        } else {
                          // Engelle
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Kullanıcıyı Engelle'),
                              content: Text('$name engellensin mi?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('İptal')),
                                TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Engelle', style: TextStyle(color: Colors.red))),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            await ref.read(blockServiceProvider).blockUser(
                              currentUserId: currentUser.$id,
                              targetUserId: widget.otherUserId,
                            );
                            if (context.mounted) context.pop(); // Sayfadan çık
                          }
                        }
                        ref.invalidate(blockStatusProvider);
                      },
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_,__) => const SizedBox.shrink(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}