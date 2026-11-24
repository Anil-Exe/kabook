import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../services/image_upload_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../../data/block_service.dart';

class BlockedUsersPage extends ConsumerWidget {
  const BlockedUsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider).value;

    if (currentUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final blockedUsersAsync = ref.watch(blockedUsersProvider(currentUser.$id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Engellenen Kullanıcılar'),
      ),
      body: blockedUsersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (users) {
          if (users.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.block, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Engellenen kullanıcı yok.', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final user = users[index];
              final userId = user['userId'];
              final name = user['displayName'] ?? 'Kullanıcı';
              final username = user['username'] ?? '';
              final photoId = user['photoId'];

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.brandGreen.withOpacity(0.1),
                  backgroundImage: photoId != null
                      ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId))
                      : null,
                  child: photoId == null
                      ? Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(color: AppColors.brandGreen, fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('@$username'),
                trailing: ElevatedButton(
                  onPressed: () async {
                    await _handleUnblock(context, ref, currentUser.$id, userId, name);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[200],
                    foregroundColor: Colors.black,
                    elevation: 0,
                  ),
                  child: const Text('Engeli Kaldır'),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _handleUnblock(BuildContext context, WidgetRef ref, String currentUserId, String blockedUserId, String name) async {
    try {
      await ref.read(blockServiceProvider).unblockUser(
            currentUserId: currentUserId,
            targetUserId: blockedUserId,
          );
      
      // Listeyi yenile
      ref.invalidate(blockedUsersProvider(currentUserId));
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name kullanıcısının engeli kaldırıldı')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }
}