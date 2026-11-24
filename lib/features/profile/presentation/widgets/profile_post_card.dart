import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:kabook_app/models/post_model.dart';
import '../../../../core/theme/app_theme.dart';

/// Profil sayfası için gönderi kartı (basitleştirilmiş)
class ProfilePostCard extends StatelessWidget {
  final Post post;

  const ProfilePostCard({
    super.key,
    required this.post,
  });

  String _formatTime(DateTime date) {
    return timeago.format(date, locale: 'tr');
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              post.content,
              style: const TextStyle(fontSize: 16),
            ),
            if (post.imageUrl != null && post.imageUrl!.isNotEmpty) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  post.imageUrl!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const SizedBox(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  _formatTime(post.createdAt),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Icon(
                      Icons.favorite,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                    const SizedBox(width: 4),
                    Text('${post.likesCount}'),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.comment,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                    const SizedBox(width: 4),
                    Text('${post.commentsCount}'),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
