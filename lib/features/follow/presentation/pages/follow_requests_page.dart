import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../data/follow_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../../services/image_upload_service.dart';
import '../../../../core/theme/app_theme.dart';

final pendingRequestsProvider = FutureProvider((ref) async {
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return [];
  return ref.read(followServiceProvider).getPendingRequests(user.$id);
});

class FollowRequestsPage extends ConsumerWidget {
  const FollowRequestsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(pendingRequestsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Takip İstekleri')),
      body: requestsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (requests) {
          if (requests.isEmpty) return const Center(child: Text('Bekleyen istek yok.'));
          
          return ListView.builder(
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final req = requests[index];
              final followerId = req.data['followerId'];
              
              return _RequestItem(
                requestId: req.$id,
                followerId: followerId,
                onAction: () => ref.invalidate(pendingRequestsProvider),
              );
            },
          );
        },
      ),
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
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İstek kabul edildi')));
                    }
                  } catch (e) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                onPressed: () async {
                  try {
                    await ref.read(followServiceProvider).unfollowUser(followDocId: requestId);
                    onAction();
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İstek reddedildi')));
                  } catch (e) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
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
