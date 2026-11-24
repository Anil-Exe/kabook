import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../services/image_upload_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../follow/data/follow_service.dart';
import '../../../../core/theme/app_theme.dart';

// Bekleyen istekleri çeken provider
final notificationPendingRequestsProvider = FutureProvider.autoDispose((ref) async {
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return [];
  return ref.read(followServiceProvider).getPendingRequests(user.$id);
});

class FollowRequestsSection extends ConsumerWidget {
  const FollowRequestsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(notificationPendingRequestsProvider);

    return requestsAsync.when(
      data: (requests) {
        if (requests.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Takip İstekleri (${requests.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: requests.length,
              itemBuilder: (context, index) {
                final req = requests[index];
                final followerId = req.data['followerId'];
                
                return _RequestItem(
                  requestId: req.$id,
                  followerId: followerId,
                  onAction: () => ref.invalidate(notificationPendingRequestsProvider),
                );
              },
            ),
            const Divider(height: 1),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _RequestItem extends ConsumerWidget {
  final String requestId;
  final String followerId;
  final VoidCallback onAction;

  const _RequestItem({
    required this.requestId,
    required this.followerId,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProvider(followerId));

    return userAsync.when(
      data: (userDoc) {
        final data = userDoc.data;
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: data['photoId'] != null
                ? CachedNetworkImageProvider(MediaService.getFileUrl(data['photoId']))
                : null,
            child: data['photoId'] == null ? const Icon(Icons.person) : null,
          ),
          title: Text(data['displayName'] ?? 'Kullanıcı'),
          subtitle: Text('@${data['username']}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.check, color: AppColors.brandGreen),
                onPressed: () async {
                  try {
                    await ref.read(followServiceProvider).acceptRequest(requestId);
                    onAction();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                onPressed: () async {
                  try {
                    await ref.read(followServiceProvider).unfollowUser(followDocId: requestId);
                    onAction();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
                  }
                },
              ),
            ],
          ),
          onTap: () => context.push('/profile/$followerId'),
        );
      },
      loading: () => const ListTile(leading: CircleAvatar(), title: Text('Yükleniyor...')),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}