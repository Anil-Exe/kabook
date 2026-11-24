import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/post_model.dart';
import '../../data/providers/post_providers.dart';
import '../widgets/post_card.dart';

/// Belirli bir hashtag'e ait gönderileri listeleyen sayfa
class HashtagPage extends ConsumerStatefulWidget {
  final String tag;

  const HashtagPage({super.key, required this.tag});

  @override
  ConsumerState<HashtagPage> createState() => _HashtagPageState();
}

class _HashtagPageState extends ConsumerState<HashtagPage> {
  late Future<List<Post>> _postsFuture;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  void _loadPosts() {
    _postsFuture = ref.read(postServiceProvider).getPostsByTag(widget.tag);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('#${widget.tag}'),
        centerTitle: true,
      ),
      body: FutureBuilder<List<Post>>(
        future: _postsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Hata: ${snapshot.error}'));
          }

          final posts = snapshot.data ?? [];

          if (posts.isEmpty) {
            return const Center(child: Text('Bu etiketle henüz gönderi paylaşılmamış.'));
          }

          return ListView.builder(
            itemCount: posts.length,
            itemBuilder: (context, index) => PostCard(post: posts[index]),
          );
        },
      ),
    );
  }
}