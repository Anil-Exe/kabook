import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../follow/data/follow_service.dart';
import '../../../messages/data/message_providers.dart';
import '../../../../services/share_service.dart';
import '../../../../core/config/appwrite_config.dart';
import '../../../../services/appwrite_service.dart';
import '../../../../services/image_upload_service.dart';

class SharePostSheet extends ConsumerStatefulWidget {
  final String postId;
  final String postContent;

  const SharePostSheet({
    super.key,
    required this.postId,
    required this.postContent,
  });

  @override
  ConsumerState<SharePostSheet> createState() => _SharePostSheetState();
}

class _SharePostSheetState extends ConsumerState<SharePostSheet> {
  String get _postUrl => 'https://kabook.app/post/${widget.postId}';
  String get _shareText => '${widget.postContent}\n\n$_postUrl';

  @override
  Widget build(BuildContext context) {
    final currentUserAsync = ref.watch(currentUserProvider);
    final shareService = ref.read(shareServiceProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(
              child: Text(
                'Paylaş',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ),

          /// HARİCİ PAYLAŞIM
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _ShareOption(
                  icon: Icons.chat,
                  label: 'WhatsApp',
                  color: const Color(0xFF25D366),
                  onTap: () async {
                    Navigator.pop(context);
                    await shareService.shareToWhatsApp(_shareText);
                  },
                ),
                _ShareOption(
                  icon: Icons.camera_alt_outlined,
                  label: 'Instagram',
                  color: const Color(0xFFE1306C),
                  onTap: () async {
                    Navigator.pop(context);
                    await shareService.openInstagramDM(_shareText);
                  },
                ),
                _ShareOption(
                  icon: Icons.copy,
                  label: 'Kopyala',
                  color: Colors.blue,
                  onTap: () async {
                    await shareService.copyLink(_postUrl);
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Bağlantı kopyalandı')),
                      );
                    }
                  },
                ),
                _ShareOption(
                  icon: Icons.ios_share,
                  label: 'Diğer',
                  color: isDark ? Colors.white : Colors.black87,
                  onTap: () async {
                    Navigator.pop(context);
                    await shareService.shareSystem(_shareText);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Takip Ettiklerine Gönder',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ),

          /// UYGULAMA İÇİ PAYLAŞIM
          Expanded(
            child: currentUserAsync.when(
              data: (user) {
                if (user == null) {
                  return const Center(child: Text('Giriş yapmalısınız'));
                }

                return FutureBuilder(
                  future: ref.read(followServiceProvider).getFollowing(user.$id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final followingDocs = snapshot.data ?? [];

                    if (followingDocs.isEmpty) {
                      return const Center(
                        child: Text('Henüz kimseyi takip etmiyorsunuz.'),
                      );
                    }

                    return ListView.builder(
                      itemCount: followingDocs.length,
                      itemBuilder: (context, index) {
                        final doc = followingDocs[index];
                        final targetUserId = doc.data['followingId'];

                        return Consumer(
                          builder: (context, ref, _) {
                            final userAsync =
                                ref.watch(userProfileProvider(targetUserId));

                            return userAsync.when(
                              data: (targetUser) {
                                final data = targetUser ?? {};
                                final name =
                                    data['displayName'] ?? 'Kullanıcı';
                                final username =
                                    data['username'] ?? '';
                                
                                // 1. Önce profileImageUrl (Tam URL) var mı bak
                                String? avatarUrl = data['profileImageUrl'];
                                
                                // 2. Yoksa photoId (Dosya ID) var mı bak ve URL üret
                                if (avatarUrl == null || avatarUrl.isEmpty) {
                                  final photoId = data['photoId'];
                                  if (photoId != null) {
                                    avatarUrl = MediaService.getFileUrl(photoId);
                                  }
                                }

                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                                    child: avatarUrl == null ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?') : null,
                                  ),
                                  title: Text(name),
                                  subtitle: Text('@$username'),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.send,
                                      color: AppColors.primaryGreen,
                                    ),
                                    onPressed: () async {
                                      try {
                                        // 1. Get or create the direct chat to get the chatId
                                        final chatDoc = await ref.read(messageServiceProvider).getOrCreateDirectChat(
                                            currentUserId: user.$id,
                                            targetUserId: targetUserId,
                                        );
                                        final chatId = chatDoc.$id;

                                        // 2. Send the message using the service
                                        await ref.read(messageServiceProvider).sendMessage(
                                          chatId: chatId,
                                          senderId: user.$id,
                                          content: _shareText,
                                          type: 'text', // A shared post is just a text message with a link.
                                        );

                                        if (context.mounted) {
                                          context.pop();
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text('$name kişisine gönderildi'),
                                            ),
                                          );
                                        }

                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(content: Text('Hata: $e')),
                                          );
                                        }
                                      }
                                    },
                                  ),
                                );
                              },
                              loading: () => const ListTile(
                                title: Text('Yükleniyor...'),
                              ),
                              error: (_, __) => const SizedBox.shrink(),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Center(child: Text('Oturum hatası')),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ShareOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
