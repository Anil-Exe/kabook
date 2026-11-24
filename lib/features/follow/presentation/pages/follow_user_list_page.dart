import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:appwrite/models.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../services/image_upload_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../../data/follow_service.dart';
import '../widgets/follow_button.dart';
import '../../../../core/theme/app_theme.dart';

class FollowListParams {
  final String userId;
  final String type;
  final String? query;

  FollowListParams({required this.userId, required this.type, this.query});

  @override
  bool operator ==(Object other) =>
      other is FollowListParams &&
      other.userId == userId &&
      other.type == type &&
      other.query == query;

  @override
  int get hashCode => Object.hash(userId, type, query);
}

final followListProvider = FutureProvider.family.autoDispose<List<Document>, FollowListParams>((ref, params) {
  final service = ref.read(followServiceProvider);
  
  // Arama varsa arama fonksiyonunu kullan
  if (params.query != null && params.query!.isNotEmpty) {
    return service.searchInFollowList(
      userId: params.userId,
      type: params.type,
      query: params.query!,
    );
  }

  if (params.type == 'followers') {
    return service.getFollowers(params.userId);
  } else {
    return service.getFollowing(params.userId);
  }
});

class FollowUserListPage extends ConsumerStatefulWidget {
  final String userId;
  final String type; // 'followers' veya 'following'

  const FollowUserListPage({super.key, required this.userId, required this.type});

  @override
  ConsumerState<FollowUserListPage> createState() => _FollowUserListPageState();
}

class _FollowUserListPageState extends ConsumerState<FollowUserListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.type == 'followers' ? 'Takipçiler' : 'Takip Edilenler';
    
    final currentUser = ref.watch(currentUserProvider).value;
    final listAsync = ref.watch(followListProvider(
      FollowListParams(userId: widget.userId, type: widget.type, query: _searchQuery),
    ));

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          // 🔍 Arama Çubuğu
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '$title içinde ara...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Theme.of(context).cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim();
                });
              },
            ),
          ),
          
          // 📋 Liste
          Expanded(
            child: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (documents) {
          if (documents.isEmpty) {
            return Center(
              child: Text(_searchQuery.isEmpty 
                  ? '$title bulunamadı.' 
                  : 'Sonuç bulunamadı.'),
            );
          }

          return ListView.builder(
            itemCount: documents.length,
            itemBuilder: (context, index) {
              final doc = documents[index];
              // Hangi user ID'yi göstereceğiz?
              // Eğer followers listesiyse, followerId (takip eden) gösterilir.
              // Eğer following listesiyse, followingId (takip edilen) gösterilir.
              final targetId = widget.type == 'followers' 
                  ? doc.data['followerId'] 
                  : doc.data['followingId'];

              // Takipçi çıkarma yetkisi: Kendi profilimse ve liste 'followers' ise
              final canRemove = (currentUser?.$id == widget.userId) && (widget.type == 'followers');

              return _UserListItem(
                userId: targetId,
                canRemove: canRemove,
                onRemove: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Takipçiyi Çıkar'),
                      content: const Text('Bu kişiyi takipçilerinden çıkarmak istediğine emin misin?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Çıkar', style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    try {
                      await ref.read(followServiceProvider).removeFollower(doc.$id);
                      
                      // Listeyi yenile
                      ref.invalidate(followListProvider(
                        FollowListParams(userId: widget.userId, type: widget.type, query: _searchQuery),
                      ));
                      
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Takipçi çıkarıldı')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('İşlem başarısız: $e')),
                        );
                      }
                    }
                  }
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

class _UserListItem extends ConsumerWidget {
  final String userId;
  final bool canRemove;
  final VoidCallback? onRemove;

  const _UserListItem({
    required this.userId,
    this.canRemove = false,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProvider(userId));

    return userAsync.when(
      loading: () => const ListTile(leading: CircleAvatar(), title: Text("Yükleniyor...")),
      error: (_, __) => const SizedBox.shrink(),
      data: (userDoc) {
        final data = userDoc.data;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.brandGreen.withOpacity(0.1),
            backgroundImage: data['photoId'] != null
                ? CachedNetworkImageProvider(MediaService.getFileUrl(data['photoId']))
                : null,
            child: data['photoId'] == null
                ? Text((data['displayName'] as String)[0].toUpperCase(), style: const TextStyle(color: AppColors.brandGreen))
                : null,
          ),
          title: Text(data['displayName'], style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('@${data['username']}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canRemove)
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.grey),
                  onPressed: onRemove,
                  tooltip: 'Çıkar',
                ),
              SizedBox(
                width: 110,
                height: 35,
                child: FollowButton(targetUserId: userId),
              ),
            ],
          ),
          onTap: () => context.push('/profile/$userId'),
        );
      },
    );
  }
}