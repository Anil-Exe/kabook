import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/appwrite_config.dart';
import '../../../../models/post_model.dart';
import '../../../../services/appwrite_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../widgets/post_card.dart';

/// 🎣 Beğenilen gönderileri çeken Provider
final likedPostsProvider = FutureProvider.autoDispose<List<Post>>((ref) async {
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return [];

  final databases = AppwriteService.databases;
  // 'likes' dizisinde kullanıcının ID'si olan gönderileri getir
  final result = await databases.listDocuments(
    databaseId: AppwriteConfig.databaseId,
    collectionId: AppwriteConfig.postsCollectionId,
    queries: [
      Query.equal('likes', user.$id),
      Query.orderDesc('\$createdAt'),
    ],
  );
  
  return result.documents.map((doc) {
    final data = Map<String, dynamic>.from(doc.data);
    data['\$id'] = doc.$id;
    data['\$createdAt'] = doc.$createdAt;
    return Post.fromMap(data);
  }).toList();
});

class LikedPostsPage extends ConsumerWidget {
  const LikedPostsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(likedPostsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Beğendiklerim'),
      ),
      body: postsAsync.when(
        data: (posts) {
          if (posts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.favorite_border, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text('Henüz hiçbir gönderiyi beğenmedin.', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index];
              return GestureDetector(
                onTap: () {
                  context.push('/post-details/${post.id}', extra: post);
                },
                child: PostCard(post: post),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Padding(padding: const EdgeInsets.all(16), child: Text('Hata: $e', textAlign: TextAlign.center))),
      ),
    );
  }
}