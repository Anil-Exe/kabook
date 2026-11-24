import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:appwrite/models.dart' as models;

import '../../../../core/theme/app_theme.dart';
import '../../../auth/data/auth_providers.dart';
import '../../data/providers/post_providers.dart';

class MyCommentsPage extends ConsumerWidget {
  const MyCommentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider).value;

    if (currentUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final commentsAsync = ref.watch(userCommentsProvider(currentUser.$id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yorumlarım'),
      ),
      body: commentsAsync.when(
        data: (comments) {
          if (comments.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.comment_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Henüz hiç yorum yapmadın.', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: comments.length,
            itemBuilder: (context, index) {
              final comment = comments[index];
              return _CommentCard(comment: comment);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hata: $e')),
      ),
    );
  }
}

class _CommentCard extends StatelessWidget {
  final models.Document comment;

  const _CommentCard({required this.comment});

  @override
  Widget build(BuildContext context) {
    final content = comment.data['content'] as String? ?? '';
    final createdAt = comment.data['\$createdAt'] as String?;
    final postId = comment.data['postId'] as String;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          // İlgili postun detay sayfasına git
          context.push('/post/$postId');
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.reply, size: 16, color: AppColors.primaryGreen),
                  const SizedBox(width: 8),
                  Text(
                    'Bir gönderiye yorum yaptın',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (createdAt != null)
                    Text(
                      timeago.format(DateTime.parse(createdAt), locale: 'tr'),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                content,
                style: const TextStyle(fontSize: 15),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}