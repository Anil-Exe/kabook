import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/data/auth_providers.dart';
import '../../data/block_service.dart';

/// Kullanıcının engellenip engellenmediğini kontrol eden provider
final isBlockedProvider = FutureProvider.family<String?, String>((ref, targetUserId) async {
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return null;
  
  final blockDoc = await ref.read(blockServiceProvider).getBlockDocument(user.$id, targetUserId);
  return blockDoc?.$id; // Engelliyse ID döner, değilse null
});

class BlockButton extends ConsumerWidget {
  final String targetUserId;
  final String targetUserName;

  const BlockButton({
    super.key, 
    required this.targetUserId,
    this.targetUserName = 'Kullanıcıyı',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockState = ref.watch(isBlockedProvider(targetUserId));
    final currentUser = ref.watch(currentUserProvider).value;

    // Kendimizi engelleyemeyiz
    if (currentUser == null || currentUser.$id == targetUserId) return const SizedBox.shrink();

    return blockState.when(
      data: (blockDocId) {
        final isBlocked = blockDocId != null;
        
        return IconButton(
          icon: Icon(
            isBlocked ? Icons.block : Icons.block_outlined,
            color: isBlocked ? Colors.red : Colors.grey,
          ),
          tooltip: isBlocked ? 'Engeli Kaldır' : 'Engelle',
          onPressed: () async {
            if (isBlocked) {
              // Unblock
              await ref.read(blockServiceProvider).unblockUser(blockDocId: blockDocId);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Engel kaldırıldı')));
              }
            } else {
              // Block confirm
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('$targetUserName engellensin mi?'),
                  content: const Text('Engellediğin kişiler senin gönderilerini göremez ve sana mesaj atamaz.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true), 
                      child: const Text('Engelle', style: TextStyle(color: Colors.red))
                    ),
                  ],
                ),
              );
              
              if (confirm == true) {
                await ref.read(blockServiceProvider).blockUser(
                  currentUserId: currentUser.$id, 
                  targetUserId: targetUserId
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kullanıcı engellendi')));
                }
              }
            }
            // UI'ı güncelle
            ref.invalidate(isBlockedProvider(targetUserId));
          },
        );
      },
      loading: () => const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => const Icon(Icons.error_outline),
    );
  }
}