import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/post_model.dart';
import '../../post/data/providers/post_providers.dart'; // postServiceProvider buradan geliyor

/// Gönderi listesi provider'ı (REALTIME)
/// Artık PostService'in stream özelliğini kullanıyor
final postsProvider = StreamProvider<List<Post>>((ref) {
  final postService = ref.watch(postServiceProvider);
  return postService.getPostsStream();
});

/// Kullanıcının gönderileri provider'ı
final userPostsProvider = FutureProvider.family<List<Post>, String>((ref, userId) async {
  final postService = ref.watch(postServiceProvider);
  // PostService'e getUserPosts eklenmeli veya mevcut sorgu kullanılmalı
  // Şimdilik stream'den filtreleyerek veya direkt sorgu ile:
  final allPosts = await postService.getPosts();
  return allPosts.where((p) => p.userId == userId).toList();
});

/// Gönderi beğeni durumu provider'ı

/// 📌 Post detayı provider'ı
final postDetailsProvider = FutureProvider.family<Post, String>((ref, postId) async {
  final postService = ref.watch(postServiceProvider);
  return postService.getPost(postId);
});
