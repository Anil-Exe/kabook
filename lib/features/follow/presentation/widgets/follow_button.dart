import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/follow_service.dart';
import '../../../auth/data/auth_providers.dart';

// Takip durumunu izleyen provider
final followStatusProvider = FutureProvider.family<Map<String, dynamic>?, String>((ref, targetUserId) async {
  final currentUser = ref.watch(currentUserProvider).value;
  if (currentUser == null) return null;
  
  final service = ref.read(followServiceProvider);
  final doc = await service.getFollowStatus(currentUser.$id, targetUserId);
  
  if (doc == null) return null;
  return {'docId': doc.$id, 'status': doc.data['status']};
});

class FollowButton extends ConsumerWidget {
  final String targetUserId;

  const FollowButton({super.key, required this.targetUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider).value;
    final followStatusAsync = ref.watch(followStatusProvider(targetUserId));

    if (currentUser == null || currentUser.$id == targetUserId) {
      return const SizedBox.shrink(); // Kendi profilimizse buton yok (Düzenle butonu var zaten)
    }

    return followStatusAsync.when(
      loading: () => const Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      error: (e, _) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () async {
            final service = ref.read(followServiceProvider);
            try {
              await service.followUser(currentUserId: currentUser.$id, targetUserId: targetUserId);
              ref.invalidate(followStatusProvider(targetUserId));
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('İşlem başarısız: $e')));
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text("Takip Et", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
      data: (followData) {
        final isFollowing = followData != null;
        final status = followData?['status'];
        final docId = followData?['docId'];

        String text = "Takip Et";
        Color bgColor = Colors.blue;
        Color textColor = Colors.white;

        if (isFollowing) {
          if (status == 'approved') {
            text = "Takip Ediliyor";
            bgColor = Colors.grey.shade200;
            textColor = Colors.black;
          } else if (status == 'pending') {
            text = "İstek Gönderildi";
            bgColor = Colors.grey.shade200;
            textColor = Colors.grey;
          }
        }

        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () async {
              final service = ref.read(followServiceProvider);
              try {
                // Eğer istek gönderilmişse (pending), geri çekme onayı iste
                if (isFollowing && status == 'pending') {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('İsteği Geri Çek'),
                      content: const Text('Takip isteğini iptal etmek istiyor musun?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hayır')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Evet', style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  );
                  if (confirm != true) return;
                }

                if (isFollowing) {
                  // Unfollow
                  await service.unfollowUser(followDocId: docId);
                } else {
                  // Follow
                  await service.followUser(currentUserId: currentUser.$id, targetUserId: targetUserId);
                }
                // UI'ı güncelle
                ref.invalidate(followStatusProvider(targetUserId));
                // Sayaçları güncelle (ProfilePage'deki provider'ları tetiklemek için gerekebilir)
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('İşlem başarısız: $e')));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: bgColor,
              foregroundColor: textColor,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }
}
