import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart'; // 🟢 Eklendi
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:timeago/timeago.dart' as timeago;
import '../../../../core/theme/app_theme.dart';
import '../../../../services/database_service.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/image_upload_service.dart';
import '../../../post/data/providers/post_providers.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../post/presentation/widgets/share_post_sheet.dart';
import 'mention_text.dart';
import 'feed_video_player.dart';
import '../pages/reels_page.dart'; // ReelsPage erişimi için (veya route)

/// Gönderi kartı widget'ı
class PostCard extends ConsumerStatefulWidget {
  final models.Document post;

  const PostCard({
    super.key,
    required this.post,
  });

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  bool _isLiking = false;

  Future<void> _toggleLike() async {
    final currentUser = await ref.read(currentUserProvider.future);
    if (currentUser == null) return;
    if (_isLiking) return;

    setState(() {
      _isLiking = true;
    });

    try {
      final databaseService = ref.read(databaseServiceProvider);
      final likes = List<String>.from(widget.post.data['likes'] ?? []);
      final isLiked = likes.contains(currentUser.$id);

      await databaseService.toggleLikePost(
        postId: widget.post.$id,
        userId: currentUser.$id,
        isLiked: isLiked,
      );

      // Realtime çalıştığı için manuel yenilemeye gerek yok ama garanti olsun diye bırakılabilir
      ref.invalidate(postsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLiking = false;
        });
      }
    }
  }

  String _formatTime(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      return timeago.format(date, locale: 'tr');
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🟢 REALTIME: Post verisini stream'den dinle
    final realtimePost = ref.watch(postDetailsProvider(widget.post.$id)).value;
    // Eğer stream'den veri geldiyse onu kullan, yoksa widget.post (listeden gelen) kullan
    final post = realtimePost ?? widget.post;

    final userId = post.data['userId'] as String? ?? '';
    final content = post.data['content'] as String? ?? '';
    final likesCount = post.data['likesCount'] as int? ?? 0;
    final commentsCount = post.data['commentsCount'] as int? ?? 0;
    final sharesCount = post.data['sharesCount'] as int? ?? 0;
    final createdAt = post.data['createdAt'] as String?;
    
    // 🎥 Medya Verileri
    final mediaType = post.data['mediaType'] as String? ?? 'image';
    final mediaIds = List<String>.from(post.data['mediaIds'] ?? []);
    final legacyImageId = post.data['imageId'] as String?;
    
    // Beğeni durumunu doğrudan post verisinden alıyoruz
    final likes = List<String>.from(post.data['likes'] ?? []);
    final currentUser = ref.watch(currentUserProvider).value;
    final isLiked = currentUser != null && likes.contains(currentUser.$id);

    // 🎥 Video Kontrolü
    // mediaType 'video' ise VEYA dosya uzantısı mp4/mov ise
    final isVideo = mediaType == 'video' || 
                    (mediaIds.isNotEmpty && (MediaService.getFileUrl(mediaIds.first).contains('.mp4') || MediaService.getFileUrl(mediaIds.first).contains('.mov')));

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () {
          if (isVideo) {
            // 🎥 Video ise Reels Sayfasına Git
            Navigator.push(context, MaterialPageRoute(builder: (_) => ReelsPage(initialPostId: widget.post.$id)));
          } else {
            // 📄 Değilse Detay Sayfasına Git
            context.push('/post/${widget.post.$id}');
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Kullanıcı bilgileri
            Consumer(
              builder: (context, ref, child) {
                final userAsync = ref.watch(userProvider(userId));

                return userAsync.when(
                  loading: () => const Row(children: [
                    CircleAvatar(radius: 24, backgroundColor: Colors.grey),
                    SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 100, height: 16, child: ColoredBox(color: Colors.grey)),
                    ]),
                  ]),
                  error: (_, __) => const Text('Kullanıcı yüklenemedi'),
                  data: (userDoc) {
                    final username = userDoc.data['username'] as String? ?? 'Kullanıcı';
                    final displayName = userDoc.data['displayName'] as String? ?? username;
                    final profileImageUrl = userDoc.data['profileImageUrl'] as String? ?? '';

                    return InkWell(
                      onTap: () => context.push('/profile/$userId'),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundImage: profileImageUrl.isNotEmpty
                                ? NetworkImage(profileImageUrl)
                                : null,
                            child: profileImageUrl.isEmpty
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  '@$username',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (createdAt != null)
                            Text(
                              _formatTime(createdAt),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 12),
            // Gönderi içeriği
            MentionText(
              text: content,
              style: const TextStyle(fontSize: 16),
              mentionColor: AppColors.primaryGreen,
            ),
            
            // 🖼️ MEDYA ALANI (Video veya Resim)
            if (mediaIds.isNotEmpty || legacyImageId != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Builder(
                  builder: (context) {
                    // Kullanılacak dosya ID'si (yeni sistem veya eski sistem)
                    final fileId = mediaIds.isNotEmpty ? mediaIds.first : legacyImageId!;
                    final fileUrl = MediaService.getFileUrl(fileId);

                    if (mediaType == 'video') {
                      // 🎥 Video Oynatıcı
                      return GestureDetector(
                        onTap: () {
                          // Videoya tıklayınca Reels sayfasına yönlendir
                          Navigator.push(context, MaterialPageRoute(builder: (_) => ReelsPage(initialPostId: widget.post.$id)));
                        },
                        child: FeedVideoPlayer(videoUrl: fileUrl),
                      );
                    } else {
                      // 🖼️ Resim Gösterici (Çoklu veya Tekli)
                      if (mediaIds.length > 1) {
                        // Çoklu Resim (Galeri)
                        return _HomeImageGallery(imageIds: mediaIds);
                      } else {
                        // Tek Resim
                        return _HomeSingleImage(imageId: fileId);
                      }
                    }
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Etkileşim butonları
            Row(
              children: [
                // Beğeni butonu
                InkWell(
                  onTap: _toggleLike,
                  child: Row(
                    children: [
                      Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked
                            ? Colors.red
                            : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                      const SizedBox(width: 4),
                      Text('$likesCount'),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                // Yorum butonu
                InkWell(
                  onTap: () {
                    if (isVideo) {
                      // Video ise Reels'e git (orada yorumlar açılabilir)
                      Navigator.push(context, MaterialPageRoute(builder: (_) => ReelsPage(initialPostId: widget.post.$id)));
                    } else {
                      context.push('/post/${widget.post.$id}');
                    }
                  },
                  child: Row(
                    children: [
                      Icon(
                        Icons.comment_outlined,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                      const SizedBox(width: 4),
                      Text('$commentsCount'),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                // Paylaş butonu
                InkWell(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (context) => SharePostSheet(postId: widget.post.$id, postContent: content),
                    );
                  },
                  child: Row(
                    children: [
                      Icon(
                        Icons.share_outlined,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                      const SizedBox(width: 4),
                      Text('$sharesCount'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// 🖼️ Tek Resim Widget'ı (Home Modülü İçin)
class _HomeSingleImage extends StatelessWidget {
  final String imageId;
  const _HomeSingleImage({required this.imageId});

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: MediaService.getFileUrl(imageId),
      fit: BoxFit.cover,
      width: double.infinity,
      placeholder: (context, url) => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
      errorWidget: (context, url, error) => const SizedBox.shrink(),
    );
  }
}

/// 📸 Kaydırılabilir Galeri (Dump) Widget'ı (Home Modülü İçin)
class _HomeImageGallery extends StatefulWidget {
  final List<String> imageIds;
  const _HomeImageGallery({required this.imageIds});

  @override
  State<_HomeImageGallery> createState() => _HomeImageGalleryState();
}

class _HomeImageGalleryState extends State<_HomeImageGallery> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 350, // Galeri yüksekliği
      child: Stack(
        children: [
          PageView.builder(
            itemCount: widget.imageIds.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              return _HomeSingleImage(imageId: widget.imageIds[index]);
            },
          ),
          // Sayfa Göstergesi (Chip)
          if (widget.imageIds.length > 1)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_currentIndex + 1}/${widget.imageIds.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
