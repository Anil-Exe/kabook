import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart'; // 🟢 Auto-play için gerekli

import '../../../../models/post_model.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../utils/time_ago.dart';
import '../../../../services/post_service.dart';
import '../../data/providers/post_providers.dart';
import '../../../../services/image_upload_service.dart'; // MediaService
import 'comments_sheet.dart'; // Yeni import
import '../../../notifications/data/notification_service.dart';
import '../pages/post_details_page.dart';
import '../../../home/data/feed_provider.dart'; // Feed provider importu
import 'share_post_sheet.dart';
import '../../../home/presentation/widgets/mention_text.dart';
import '../../../home/presentation/pages/reels_page.dart';
import '../../../home/data/feed_provider.dart'; // Reels provider için

class PostCard extends ConsumerStatefulWidget {
  final Post post;
  final bool isEmbedded; // İç içe kullanım için (Repost içinde orijinal kart)

  const PostCard({
    super.key, 
    required this.post,
    this.isEmbedded = false,
  });

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  bool? _optimisticIsLiked;
  int? _optimisticLikesCount;
  int? _optimisticRepostsCount;

  @override
  void didUpdateWidget(PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Yeni veriler provider'dan geldiğinde lokal durumu sıfırla
    if (widget.post != oldWidget.post) {
      _optimisticIsLiked = null;
      _optimisticLikesCount = null;
      _optimisticRepostsCount = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔄 REPOST KONTROLÜ
    // Eğer bu bir repost ise ve embedded değilse (yani ana kart ise), özel görünüm çiz.
    if (widget.post.isRepost && !widget.isEmbedded) {
      return _buildRepostWrapper(context);
    }

    final userAsync = ref.watch(userProvider(widget.post.userId));
    final currentUser = ref.watch(currentUserProvider).value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Embedded kartlar için stil ayarları
    final cardColor = widget.isEmbedded 
        ? (isDark ? Colors.grey[900] : Colors.grey[50]) 
        : null;
    
    final cardBorder = widget.isEmbedded
        ? BorderSide(color: Colors.grey.withOpacity(0.2))
        : null;

    final cardMargin = widget.isEmbedded
        ? EdgeInsets.zero
        : const EdgeInsets.only(bottom: 16);

    return Card(
      margin: cardMargin,
      color: cardColor,
      elevation: widget.isEmbedded ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: cardBorder ?? BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => PostDetailsPage(postId: widget.post.id)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ... (Mevcut içerik buraya gelecek, aşağıda devam ediyor)
              _buildCardContent(context, userAsync, currentUser, isDark),
            ],
          ),
        ),
      ),
    );
  }

  /// 🔄 Repost Wrapper (X Tarzı Görünüm)
  Widget _buildRepostWrapper(BuildContext context) {
    final reposterAsync = ref.watch(userProvider(widget.post.userId));

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Repost Başlığı (X repostladı)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
            children: [
              const Icon(Icons.repeat, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              reposterAsync.when(
                data: (user) => GestureDetector(
                  onTap: () => context.push('/profile/${widget.post.userId}'),
                  child: Text(
                    '${user.data['displayName']} repostladı',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_,__) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),

        // 2. Orijinal Post Kartı
        if (widget.post.originalPostId != null)
          ref.watch(postDetailsProvider(widget.post.originalPostId!)).when(
            data: (doc) {
              final originalPost = Post.fromMap(doc.toMap());
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: PostCard(post: originalPost, isEmbedded: true),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.grey),
                  SizedBox(width: 8),
                  Text('Orijinal gönderiye ulaşılamıyor.', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ),
      ],
      ),
    );
  }

  /// 📄 Kart İçeriği (Mevcut build metodunun içi buraya taşındı)
  Widget _buildCardContent(
    BuildContext context, 
    AsyncValue<dynamic> userAsync, 
    dynamic currentUser, 
    bool isDark
  ) {
    final post = widget.post;
    
    // Orijinal durumu al ve lokal iyimser güncellemelerle (optimistic updates) birleştir
    final bool actualIsLiked = currentUser != null && post.likes.contains(currentUser.$id);
    final bool isLiked = _optimisticIsLiked ?? actualIsLiked;
    final int likesCount = _optimisticLikesCount ?? post.likesCount;
    final int repostsCount = _optimisticRepostsCount ?? post.repostsCount;

    final bool isOwner = currentUser != null && post.userId == currentUser.$id;

    return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ///  KULLANICI
            userAsync.when(
              data: (userDoc) {
                final displayName =
                    userDoc.data['displayName'] as String? ?? 'Kullanıcı';
                final role = userDoc.data['role'] as String? ?? 'Öğrenci';
                final photoId = userDoc.data['photoId'] as String?; // 🟢 Şema uyumu

                final roleColor = role == 'Öğrenci'
                    ? AppColors.softGreen
                    : AppColors.primaryGreen;

                return GestureDetector(
                  onTap: () => context.push('/profile/${post.userId}'),
                  child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.brandGreen.withOpacity(0.2),
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: AppColors.brandGreen.withOpacity(0.1),
                        backgroundImage: photoId != null
                            ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId))
                            : null,
                        child: photoId == null
                            ? Text(
                                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'K',
                                style: const TextStyle(
                                  color: AppColors.brandGreen,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                          Text(
                            '@${userDoc.data['username'] ?? ''}${post.university != null && post.university!.isNotEmpty ? ' • ${post.university}' : ''} • ${timeAgo(post.createdAt)}',
                            style: TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.normal,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // 🗑️ SİLME / DÜZENLEME BUTONU (Sadece Sahibi)
                    if (isOwner)
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_horiz, color: Colors.grey, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onSelected: (value) {
                          if (value == 'delete') {
                            _confirmDelete(context, post.id, currentUser.$id);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [Icon(Icons.delete_outline, color: Colors.red), SizedBox(width: 8), Text('Sil')],
                            ),
                          ),
                        ],
                      ),
                  ],
                  ),
                );
              },
              loading: () => const SizedBox(
                height: 44,
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (_, __) {
                // Hata durumunda (örn: manuel eklenen postlarda user ID yoksa)
                return Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.withOpacity(0.2), width: 2),
                      ),
                      child: const CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.grey,
                        child: Icon(Icons.person, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Anonim Kullanıcı',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          // ...
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 8),

            /// 📝 POST
            if (post.content.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 4, top: 4),
                child: MentionText(
                  text: post.content,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                    fontSize: 15,
                  ),
                  mentionColor: AppColors.primaryGreen,
                ),
              ),
            
            // ✏️ DÜZENLENDİ İBARESİ
            if (post.editedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('(düzenlendi)', style: TextStyle(fontSize: 11, color: Colors.grey[400], fontStyle: FontStyle.italic)),
              ),

            /// 🖼️ MEDYA (RESİM / VİDEO / GALERİ)
            _buildMediaContent(context, post),

            /// 🏷️ ETİKETLER
            if (post.tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12, left: 4),
                child: Wrap(
                  spacing: 8,
                  children: post.tags.map((tag) => Text(
                    '#$tag',
                    style: TextStyle(color: AppColors.brandTeal, fontWeight: FontWeight.bold),
                  )).toList(),
                ),
              ),

            const SizedBox(height: 16),

            // Eğer embedded (iç içe) ise aksiyon butonlarını gösterme
            if (!widget.isEmbedded)
            /// ❤️ ETKİLEŞİM
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Action(
                  icon: isLiked
                      ? Icons.favorite
                      : Icons.favorite_border, 
                  color: isLiked ? Colors.redAccent : null,
                  count: likesCount,
                  isLike: true,
                  onTap: () async {
                    if (currentUser == null) return;

                    final wasLiked = isLiked;
                    setState(() {
                      _optimisticIsLiked = !wasLiked;
                      _optimisticLikesCount = likesCount + (wasLiked ? -1 : 1);
                    });

                    // ⚡ Zıplamayı önlemek için Optimistic Update (Ekranı anında günceller)
                    ref.read(feedPostsProvider.notifier).toggleLikeOptimistically(post.id, currentUser.$id);
                    ref.read(reelsPostsProvider.notifier).toggleLikeOptimistically(post.id, currentUser.$id);

                    try {
                      await ref.read(postServiceProvider).toggleLike(
                            post.id,
                            currentUser.$id,
                          );

                      if (!isLiked) {
                        await ref.read(notificationServiceProvider).createNotification(
                              toUserId: post.userId,
                              fromUserId: currentUser.$id,
                              type: 'like',
                              content: '${currentUser.name} gönderini beğendi',
                              eventId: post.id,
                            );
                      }
                      ref.invalidate(postDetailsProvider(post.id)); // Detay sayfasını yenile
                    } catch (e) {
                      // Hata durumunda işlemi geri al
                      if (mounted) {
                        setState(() {
                          _optimisticIsLiked = wasLiked;
                          _optimisticLikesCount = likesCount;
                        });
                      }
                      ref.read(feedPostsProvider.notifier).toggleLikeOptimistically(post.id, currentUser.$id);
                      ref.read(reelsPostsProvider.notifier).toggleLikeOptimistically(post.id, currentUser.$id);
                    }
                  },
                ),
                _Action(
                  icon: Icons.chat_bubble_outline_rounded,
                  count: post.commentsCount,
                  onTap: () {
                    if (currentUser == null) return;
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => CommentsSheet(postId: post.id, postOwnerId: post.userId),
                    );
                  },
                ),
                _Action(
                  icon: Icons.repeat_rounded,
                  count: repostsCount,
                  onTap: () async {
                    if (currentUser == null) return;
                    
                    try {
                      // 🔹 Profil verisini çek (University ID için)
                      final userProfile = await ref.read(currentUserProfileProvider.future);
                      final universityId = userProfile?['university'] as String?;

                      if (universityId == null || universityId.isEmpty) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Üniversite bilgisi bulunamadı.')),
                          );
                        }
                        return;
                      }

                      setState(() {
                        _optimisticRepostsCount = repostsCount + 1;
                      });

                      // ⚡ Optimistic Update
                      ref.read(feedPostsProvider.notifier).incrementRepostOptimistically(post.id);
                      ref.read(reelsPostsProvider.notifier).incrementRepostOptimistically(post.id);

                      await ref.read(postServiceProvider).repost(post, currentUser.$id, universityId);

                      await ref.read(notificationServiceProvider).createNotification(
                            toUserId: post.userId,
                            fromUserId: currentUser.$id,
                            type: 'repost',
                            content: '${currentUser.name} gönderini repostladı',
                            eventId: post.id,
                          );

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Repost yapıldı!')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        setState(() {
                          _optimisticRepostsCount = repostsCount;
                        });
                      }
                      
                      // Hata durumunda orjinal haline geri almak için postu db'den geri çek
                      final updatedPost = await ref.read(postServiceProvider).getPost(post.id);
                      ref.read(feedPostsProvider.notifier).updateSpecificPost(updatedPost);
                      ref.read(reelsPostsProvider.notifier).updateSpecificPost(updatedPost);

                      if (e.toString().contains('zaten paylaştınız') && context.mounted) {
                        _showUnrepostDialog(context, post.id, currentUser.$id);
                      } else if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Hata: $e')),
                        );
                      }
                    }
                  },
                ),
                // Share button (Action stiliyle uyumlu ve eşit boşluklu)
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (context) => SharePostSheet(postId: post.id, postContent: post.content),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Icon(Icons.ios_share, size: 24, color: isDark ? Colors.grey[400] : Colors.grey[700]),
                  ),
                ),
              ],
            ),
          ],
        
    );
  }

  void _confirmDelete(BuildContext context, String postId, String userId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gönderiyi Sil'),
        content: const Text('Bu gönderiyi silmek istediğine emin misin?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(postServiceProvider).deletePost(postId);
              ref.invalidate(postsProvider);
              ref.invalidate(feedPostsProvider);
              ref.invalidate(reelsPostsProvider);
            },
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showUnrepostDialog(BuildContext context, String postId, String userId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Repostu Geri Al'),
        content: const Text('Bu gönderiyi repostlamaktan vazgeçmek istiyor musun?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref.read(postServiceProvider).unrepost(postId, userId);
                
                final updatedPost = await ref.read(postServiceProvider).getPost(postId);
                ref.read(feedPostsProvider.notifier).updateSpecificPost(updatedPost);
                ref.read(reelsPostsProvider.notifier).updateSpecificPost(updatedPost);
                
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Repost geri alındı.')),
                  );
                }
              } catch (e) {
                // Hata yönetimi
              }
            },
            child: const Text('Geri Al', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// 🖼️ Medya İçeriği Oluşturucu
  Widget _buildMediaContent(BuildContext context, Post post) {
    // Medya listesini hazırla
    List<String> mediaList = List.from(post.mediaIds);
    // Geriye dönük uyumluluk: mediaIds boşsa ama imageId varsa
    if (mediaList.isEmpty && post.imageId != null && post.imageId!.isNotEmpty) {
      mediaList.add(post.imageId!);
    }

    if (mediaList.isEmpty) return const SizedBox.shrink();

    // 🟢 Video Kontrolü: mediaType 'video' ise VEYA dosya uzantısı mp4/mov ise
    // Veri tabanında mediaType 'image' kalsa bile uzantıdan kurtarırız.
    final isVideo = post.mediaType == 'video' || 
                    (mediaList.isNotEmpty && (MediaService.getFileUrl(mediaList.first).contains('.mp4') || MediaService.getFileUrl(mediaList.first).contains('.mov')));

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: isVideo
            ? FeedVideoPlayer(
                videoUrl: MediaService.getFileUrl(mediaList.first),
                postId: post.id, // 🟢 Reels'e geçiş için ID
              )
            : (mediaList.length > 1 
                ? ImageGallery(imageIds: mediaList) 
                : SingleImage(imageId: mediaList.first)),
      ),
    );
  }
}

/// 🔘 ACTION BUTTON
class _Action extends StatelessWidget {
  final IconData icon;
  final int count;
  final VoidCallback onTap;
  final Color? color;
  final bool isLike;

  const _Action({
    required this.icon,
    required this.count,
    required this.onTap,
    this.color,
    this.isLike = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Eğer color null ise (beğenilmemişse) metalik gri/gümüş tonları kullan
    final iconColor = color ?? (isDark ? Colors.grey[400] : Colors.grey[700]);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (isLike)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                child: Icon(icon, key: ValueKey(icon), size: 24, color: iconColor),
              )
            else
              Icon(icon, size: 24, color: iconColor),
            const SizedBox(width: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
              child: Text(
                '$count',
                key: ValueKey(count),
                style: TextStyle(
                  color: iconColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 🖼️ Tek Resim Widget'ı
class SingleImage extends StatelessWidget {
  final String imageId;
  const SingleImage({super.key, required this.imageId});

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

/// 📸 Kaydırılabilir Galeri (Dump) Widget'ı
class ImageGallery extends StatefulWidget {
  final List<String> imageIds;
  const ImageGallery({super.key, required this.imageIds});

  @override
  State<ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<ImageGallery> {
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
              return SingleImage(imageId: widget.imageIds[index]);
            },
          ),
          // Sayfa Göstergesi (Chip)
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

/// 🎥 Feed İçin Otomatik Oynayan Video Player
class FeedVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String? postId; // 🟢 Reels geçişi için eklendi
  const FeedVideoPlayer({super.key, required this.videoUrl, this.postId});

  @override
  State<FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends State<FeedVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isMuted = true; // 🟢 Ses durumu

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _isInitialized = true);
          _controller!.setLooping(true);
          _controller!.setVolume(0); // 🟢 Varsayılan sessiz
        }
      }).catchError((e) {
        debugPrint('Feed video error: $e');
      });
  }

  void _toggleMute() {
    if (_controller == null) return;
    setState(() {
      _isMuted = !_isMuted;
      _controller!.setVolume(_isMuted ? 0 : 1);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return Container(
        height: 300,
        color: Colors.black,
        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return VisibilityDetector(
      key: Key(widget.videoUrl),
      onVisibilityChanged: (info) {
        if (!mounted || _controller == null) return;
        // %50'den fazlası görünüyorsa oynat, yoksa durdur
        if (info.visibleFraction > 0.5) {
          if (!_controller!.value.isPlaying) {
            _controller!.play();
          }
        } else {
          if (_controller!.value.isPlaying) {
            _controller!.pause();
          }
        }
      },
      child: AspectRatio(
        aspectRatio: _controller!.value.aspectRatio,
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            VideoPlayer(_controller!),
            
            // 🟢 1. Tıklayınca Sesi Aç/Kapat
            Positioned.fill(
              child: GestureDetector(
                onTap: _toggleMute,
                child: Container(color: Colors.transparent),
              ),
            ),

            // 🟢 2. Ses İkonu (Duruma göre değişir)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isMuted ? Icons.volume_off : Icons.volume_up, 
                  color: Colors.white, 
                  size: 20
                ),
              ),
            ),
            
            // 🟢 3. Reels/Tam Ekran Butonu (Sağ Üst)
            if (widget.postId != null)
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ReelsPage(initialPostId: widget.postId)));
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.fullscreen, color: Colors.white, size: 24),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
