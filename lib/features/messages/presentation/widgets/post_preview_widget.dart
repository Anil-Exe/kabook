import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../services/image_upload_service.dart';
import '../../../post/data/providers/post_providers.dart';

class PostPreviewWidget extends ConsumerWidget {
  final String postId;

  const PostPreviewWidget({super.key, required this.postId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postAsync = ref.watch(postDetailsProvider(postId));

    return GestureDetector(
      onTap: () => context.push('/post/$postId'),
      child: Container(
        width: 220, // Mesaj baloncuğu için ideal genişlik
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: postAsync.when(
          loading: () => const SizedBox(
            height: 100,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, __) => Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey.withOpacity(0.1),
            child: const Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: Colors.grey),
                SizedBox(width: 8),
                Expanded(child: Text('Gönderiye ulaşılamıyor', style: TextStyle(fontSize: 12))),
              ],
            ),
          ),
          data: (postDoc) {
            final data = postDoc.data;
            final content = data['content'] as String? ?? '';
            final imageId = data['imageId'] as String?;
            final university = data['university'] as String?;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Varsa Resim
                if (imageId != null)
                  CachedNetworkImage(
                    imageUrl: MediaService.getFileUrl(imageId),
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: Colors.grey[200]),
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                
                // İçerik
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (university != null)
                        Text(
                          university,
                          style: TextStyle(fontSize: 10, color: AppColors.primaryGreen, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 4),
                      Text(
                        content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.arrow_forward, size: 12, color: AppColors.primaryGreen),
                          const SizedBox(width: 4),
                          Text(
                            'Gönderiyi gör',
                            style: TextStyle(fontSize: 10, color: AppColors.primaryGreen, fontWeight: FontWeight.bold),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}