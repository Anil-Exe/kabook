import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/config/appwrite_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../services/appwrite_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../notifications/data/notification_service.dart';
import '../../../../services/post_service.dart';
import '../../data/providers/post_providers.dart';
import '../../../../services/image_upload_service.dart';
import '../../../home/data/feed_provider.dart'; // Feed provider importu
import '../widgets/share_post_sheet.dart'; // SharePostSheet importu
import '../../../home/presentation/widgets/mention_text.dart';
import '../../../follow/data/follow_service.dart';
import '../widgets/post_card.dart';

class PostDetailsPage extends ConsumerStatefulWidget {
  static const String routePath = '/post/:postId';

  final String postId;
  const PostDetailsPage({super.key, required this.postId});

  @override
  ConsumerState<PostDetailsPage> createState() => _PostDetailsPageState();
}

class _PostDetailsPageState extends ConsumerState<PostDetailsPage> {
  final TextEditingController _commentController = TextEditingController();
  bool _isSending = false;

  // Etiketleme değişkenleri
  List<Document> _mentionSuggestions = [];
  bool _showMentions = false;
  String? _currentMentionQuery;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  // Metin değiştiğinde etiket kontrolü
  void _onTextChanged(String text) {
    final selection = _commentController.selection;
    if (selection.baseOffset < 0) return;

    // İmlecin solundaki kelimeyi bul
    final textBeforeCursor = text.substring(0, selection.baseOffset);
    // Boşluk veya yeni satıra göre böl
    final words = textBeforeCursor.split(RegExp(r'\s+'));
    final lastWord = words.isNotEmpty ? words.last : '';

    if (lastWord.startsWith('@')) {
      final query = lastWord.substring(1).toLowerCase();
      setState(() {
        _currentMentionQuery = query;
        _showMentions = true;
      });
      _searchUsers(query);
    } else {
      if (_showMentions) {
        setState(() {
          _showMentions = false;
          _mentionSuggestions = [];
        });
      }
    }
  }

  Future<void> _searchUsers(String query) async {
    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) return;

    try {
      final users = await ref.read(followServiceProvider).searchInFollowList(
        userId: currentUser.$id, 
        type: 'following', 
        query: query
      );
      
      // 🧹 DUPLICATE TEMİZLİĞİ: Aynı userId'ye sahip birden fazla kayıt varsa,
      // sadece en son oluşturulanı (en güncel olanı) al.
      final Map<String, Document> uniqueUsers = {};
      
      for (var doc in users) {
        final userId = doc.data['userId'] as String;
        // Eğer listede yoksa veya bu kayıt daha güncelse listeye ekle/güncelle
        if (!uniqueUsers.containsKey(userId) || 
            DateTime.parse(doc.$createdAt).isAfter(DateTime.parse(uniqueUsers[userId]!.$createdAt))) {
          uniqueUsers[userId] = doc;
        }
      }

      if (mounted) {
        setState(() {
          // Map values'larını listeye çevir
          _mentionSuggestions = uniqueUsers.values.toList();
        });
      }
    } catch (e) {
      debugPrint('Kullanıcı arama hatası: $e');
    }
  }

  void _selectMention(String username) {
    final text = _commentController.text;
    final selection = _commentController.selection;

    final textBeforeCursor = text.substring(0, selection.baseOffset);
    
    // Son kelimenin (etiketin) başlangıcını bul
    final lastWhitespace = textBeforeCursor.lastIndexOf(RegExp(r'\s'));
    final start = lastWhitespace == -1 ? 0 : lastWhitespace + 1;

    final newText = text.replaceRange(start, selection.baseOffset, '@$username ');

    _commentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + username.length + 2),
    );

    setState(() {
      _showMentions = false;
      _mentionSuggestions = [];
    });
  }

  Future<void> _sendComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) return;

    setState(() => _isSending = true);

    try {
      // Tüm mantık (Count artırma + Bildirim) servise taşındı
      await ref.read(postServiceProvider).createComment(
        widget.postId,
        currentUser.$id,
        content,
      );

      _commentController.clear();
      // UI'ı anında güncellemek için provider'ları yenile
      ref.invalidate(postCommentsProvider(widget.postId));
      ref.invalidate(postDetailsProvider(widget.postId));
      
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final postAsync = ref.watch(postDetailsProvider(widget.postId));
    final commentsAsync = ref.watch(postCommentsProvider(widget.postId));

    return Scaffold(
      appBar: AppBar(title: const Text('Gönderi')),
      body: Stack(
        children: [
          postAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (post) {
          
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(postDetailsProvider(widget.postId));
              ref.invalidate(postCommentsProvider(widget.postId));
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 100), // Alt bar için boşluk
              children: [
                // --- POST İÇERİĞİ ---
                _PostMainContent(post: post),
                
                const Divider(thickness: 1, height: 1),

                // --- YORUMLAR BAŞLIĞI ---
                commentsAsync.when(
                  data: (comments) => Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Yorumlar (${comments.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_,__) => const SizedBox.shrink(),
                ),

                // --- YORUM LİSTESİ ---
                commentsAsync.when(
                  loading: () => const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
                  error: (e, _) => Center(child: Text('Yorumlar yüklenemedi: $e')),
                  data: (comments) {
                    if (comments.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Text('Henüz yorum yok. İlk yorumu sen yap!', style: TextStyle(color: Colors.grey)),
                        ),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: comments.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        return _CommentItem(comment: comments[index], postId: widget.postId);
                      },
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),

          // --- ALT BAR (Yorum Yazma + Öneriler) ---
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // --- MENTION SUGGESTIONS (Yüzen Liste) ---
                if (_showMentions && _mentionSuggestions.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.withOpacity(0.1)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _mentionSuggestions.length,
                      itemBuilder: (context, index) {
                        final user = _mentionSuggestions[index].data;
                        // Profil resmi ID'sini al (yeni sistem photoId, eski sistem profileImageUrl)
                        final photoId = user['photoId'] ?? user['profileImageUrl'];

                        return Column(
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              leading: CircleAvatar(
                                radius: 20,
                                backgroundColor: Colors.grey[200],
                                backgroundImage: (photoId != null && photoId.isNotEmpty)
                                    ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId)) 
                                    : null,
                                child: (photoId == null || photoId.isEmpty) 
                                    ? Text(user['displayName'][0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)) 
                                    : null,
                              ),
                              title: Text(user['displayName'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                              subtitle: Text('@${user['username']}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                              onTap: () => _selectMention(user['username']),
                            ),
                            if (index != _mentionSuggestions.length - 1)
                              Divider(height: 1, indent: 70, endIndent: 16, color: Colors.grey.withOpacity(0.1)),
                          ],
                        );
                      },
                    ),
                  ),
                  ),

                // --- YORUM YAZMA ALANI ---
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2))),
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        // Mevcut kullanıcının avatarı
                        Consumer(builder: (context, ref, _) {
                          final user = ref.watch(currentUserProfileProvider).value;
                          final imageId = user?['profileImageUrl'];
                          final imageUrl = imageId != null ? AppwriteService.getFilePreviewUrl(imageId) : null;
                          return CircleAvatar(
                            radius: 18,
                            backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
                            child: imageUrl == null ? const Icon(Icons.person, size: 20) : null,
                          );
                        }),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _commentController,
                            onChanged: _onTextChanged,
                            decoration: InputDecoration(
                              hintText: 'Yanıtını gönder',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Theme.of(context).cardColor,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _isSending ? null : _sendComment,
                          icon: _isSending 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send, color: AppColors.primaryGreen),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 📌 Postun Ana İçeriği (Header, Text, Image, Stats)
class _PostMainContent extends ConsumerWidget {
  final Document post;
  const _PostMainContent({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = post.data;
    final userId = data['userId'];
    final content = data['content'] ?? '';
    final imageId = data['imageId'];
    final createdAt = DateTime.parse(post.$createdAt);
    final likesCount = data['likesCount'] ?? 0;
    final likes = List<String>.from(data['likes'] ?? []);
    final commentsCount = data['commentsCount'] ?? 0;
    final sharesCount = data['sharesCount'] ?? 0;
    
    // 🆕 Medya Verilerini Hazırla
    final mediaIds = List<String>.from(data['mediaIds'] ?? []);
    final mediaType = data['mediaType'] ?? 'image';
    // Geriye dönük uyumluluk
    if (mediaIds.isEmpty && imageId != null && imageId.isNotEmpty) {
      mediaIds.add(imageId);
    }
    final isVideo = mediaType == 'video' || 
                    (mediaIds.isNotEmpty && (MediaService.getFileUrl(mediaIds.first).contains('.mp4') || MediaService.getFileUrl(mediaIds.first).contains('.mov')));

    final userProfileAsync = ref.watch(userProfileProvider(userId));
    final currentUser = ref.watch(currentUserProvider).value;
    final isLiked = currentUser != null && likes.contains(currentUser.$id);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Post silme fonksiyonu
    Future<void> _deletePost() async {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Gönderiyi Sil'),
          content: const Text('Bu gönderiyi silmek istediğinize emin misiniz?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Sil'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        try {
          await ref.read(postServiceProvider).deletePost(post.$id);
          if (context.mounted) context.pop(); // Detay sayfasından çık
        } catch (e) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- HEADER (User Info) ---
          userProfileAsync.when(
            loading: () => const Row(children: [CircleAvatar(), SizedBox(width: 10), Text('Yükleniyor...')]),
            error: (_,__) => const Text('Kullanıcı yüklenemedi'),
            data: (user) {
              final name = user?['displayName'] ?? 'Kullanıcı';
              final username = user?['username'] ?? 'user';
              final photoId = user?['photoId'] ?? user?['profileImageUrl'];

              return Row(
                children: [
                  GestureDetector(
                    onTap: () => context.push('/profile/$userId'),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.grey[200],
                      backgroundImage: photoId != null 
                          ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId)) 
                          : null,
                      child: photoId == null ? Text(name[0].toUpperCase()) : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => context.push('/profile/$userId'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text('@$username', style: const TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                  // Sadece post sahibi ise silme menüsünü göster
                  if (currentUser?.$id == userId)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) {
                        if (value == 'delete') _deletePost();
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                            value: 'delete', child: Text('Sil', style: TextStyle(color: Colors.red))),
                      ],
                    ),
                ],
              );
            },
          ),

          const SizedBox(height: 12),

          // --- CONTENT (Text) ---
          if (content.isNotEmpty)
            MentionText(
              text: content,
              style: const TextStyle(fontSize: 18, height: 1.4),
              mentionColor: AppColors.primaryGreen, // Etiket rengi
            ),

          const SizedBox(height: 16),

          // --- MEDIA (Image/Video/Gallery) ---
          if (mediaIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: isVideo
                    ? FeedVideoPlayer(videoUrl: MediaService.getFileUrl(mediaIds.first))
                    : (mediaIds.length > 1
                        ? ImageGallery(imageIds: mediaIds)
                        : GestureDetector(
                            onTap: () {
                              final url = MediaService.getFileUrl(mediaIds.first);
                              Navigator.push(context, MaterialPageRoute(builder: (_) => _FullScreenImageViewer(imageUrl: url)));
                            },
                            child: SingleImage(imageId: mediaIds.first),
                          )),
              ),
            ),


          // --- DATE ---
          Text(
            DateFormat('HH:mm · d MMM yyyy', 'tr_TR').format(createdAt),
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),

          const Divider(height: 24),

          // --- STATS (Likes & Comments) ---
          Row(
            children: [
              // Repost Sayısı
              if (sharesCount > 0) ...[
                InkWell(
                  onTap: () => _showRepostsModal(context, ref, post.$id),
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color),
                      children: [
                        TextSpan(text: '$sharesCount ', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const TextSpan(text: 'Repost', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
              
              // Beğeni Sayısı
              InkWell(
                onTap: () => _showLikesModal(context, ref, likes),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color),
                    children: [
                      TextSpan(text: '$likesCount ', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const TextSpan(text: 'Beğeni', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const Divider(height: 24),

          // --- ACTIONS (Like, Share) ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () async {
                  if (currentUser == null) return;
                  await ref.read(postServiceProvider).toggleLike(post.$id, currentUser.$id);
                  ref.invalidate(postDetailsProvider(post.$id));
                  ref.invalidate(feedPostsProvider); // Ana akışı yenile
                  ref.invalidate(postsProvider); // Stream akışını yenile
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    color: isLiked ? Colors.redAccent : (isDark ? Colors.grey[400] : Colors.grey[700]),
                    size: 26,
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {}, // Klavyeyi açma işlevi eklenebilir
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Icon(Icons.chat_bubble_outline_rounded, size: 26, color: isDark ? Colors.grey[400] : Colors.grey[700]),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (context) => SharePostSheet(postId: post.$id, postContent: content),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Icon(Icons.ios_share, size: 26, color: isDark ? Colors.grey[400] : Colors.grey[700]),
                ),
              ),
            ],
          ),
          
          const Divider(height: 1),
        ],
      ),
    );
  }

  /// Beğenenleri Gösteren Modal
  void _showLikesModal(BuildContext context, WidgetRef ref, List<String> userIds) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        if (userIds.isEmpty) {
          return const SizedBox(height: 200, child: Center(child: Text('Henüz kimse beğenmedi.')));
        }
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Beğenenler', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: userIds.length,
                itemBuilder: (context, index) {
                  final uid = userIds[index];
                  final userAsync = ref.watch(userProfileProvider(uid));
                  
                  return userAsync.when(
                    data: (user) {
                      final name = user?['displayName'] ?? 'Kullanıcı';
                      final photoId = user?['photoId'] ?? user?['profileImageUrl'];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: photoId != null 
                              ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId)) 
                              : null
                        ),
                        title: Text(name),
                        onTap: () => context.push('/profile/$uid'),
                      );
                    },
                    loading: () => const ListTile(leading: CircleAvatar(), title: Text('...')),
                    error: (_,__) => const SizedBox.shrink(),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// Repostlayanları Gösteren Modal
  void _showRepostsModal(BuildContext context, WidgetRef ref, String postId) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Repostlayanlar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<Document>>(
                future: ref.read(postServiceProvider).getReposts(postId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Hata: ${snapshot.error}'));
                  }
                  final reposts = snapshot.data ?? [];
                  if (reposts.isEmpty) {
                    return const Center(child: Text('Henüz kimse paylaşmadı.'));
                  }

                  return ListView.builder(
                    itemCount: reposts.length,
                    itemBuilder: (context, index) {
                      final repost = reposts[index];
                      final uid = repost.data['repostUserId'];
                      
                      return Consumer(
                        builder: (context, ref, _) {
                          final userAsync = ref.watch(userProfileProvider(uid));
                          return userAsync.when(
                            data: (user) {
                              final name = user?['displayName'] ?? 'Kullanıcı';
                              final photoId = user?['photoId'] ?? user?['profileImageUrl'];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundImage: photoId != null 
                                      ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId)) 
                                      : null
                                ),
                                title: Text(name),
                                onTap: () => context.push('/profile/$uid'),
                              );
                            },
                            loading: () => const ListTile(leading: CircleAvatar(), title: Text('...')),
                            error: (_,__) => const SizedBox.shrink(),
                          );
                        }
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 📌 Tam Ekran Resim Görüntüleyici (Zoomable)
class _FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  const _FullScreenImageViewer({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true,
          minScale: 0.5,
          maxScale: 4.0,
          child: CachedNetworkImage(imageUrl: imageUrl),
        ),
      ),
    );
  }
}

/// 📌 Tekil Yorum Satırı
class _CommentItem extends ConsumerWidget {
  final Document comment;
  final String postId;
  const _CommentItem({required this.comment, required this.postId});

  Future<void> _deleteComment(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yorumu Sil'),
        content: const Text('Bu yorumu silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final databases = AppwriteService.databases;
      await databases.deleteDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.commentsCollectionId,
        documentId: comment.$id,
      );

      // Post yorum sayısını güncelle
      final postDoc = await ref.read(postDetailsProvider(postId).future);
      final currentComments = postDoc.data['commentsCount'] ?? 0;
      
      if (currentComments > 0) {
        await databases.updateDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.postsCollectionId,
          documentId: postId,
          data: {'commentsCount': currentComments - 1},
        );
      }

      ref.invalidate(postCommentsProvider(postId));
      ref.invalidate(postDetailsProvider(postId));
      ref.invalidate(feedPostsProvider); // Ana akışı yenile
      ref.invalidate(postsProvider); // Stream akışını yenile

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yorum silindi')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = comment.data;
    final userId = data['userId'];
    final content = data['content'];
    final createdAt = DateTime.parse(comment.$createdAt);
    final likes = List<String>.from(data['likes'] ?? []);
    final likesCount = data['likesCount'] ?? 0;

    final currentUser = ref.watch(currentUserProvider).value;
    final isLiked = currentUser != null && likes.contains(currentUser.$id);
    final userAsync = ref.watch(userProfileProvider(userId));

    return userAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_,__) => const SizedBox.shrink(),
      data: (user) {
        final name = user?['displayName'] ?? 'Kullanıcı';
        final username = user?['username'] ?? 'user';
        final photoId = user?['photoId'] ?? user?['profileImageUrl'];

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => context.push('/profile/$userId'),
                child: CircleAvatar(
                  radius: 20,
                  backgroundImage: photoId != null 
                      ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId)) 
                      : null,
                  child: photoId == null ? Text(name[0].toUpperCase()) : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 6),
                        Text('@$username', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(width: 6),
                        Text('· ${DateFormat('d MMM').format(createdAt)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    MentionText(
                      text: content, 
                      style: const TextStyle(fontSize: 15),
                      mentionColor: AppColors.primaryGreen,
                    ),
                  ],
                ),
              ),
              // ❤️ BEĞENİ BUTONU
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () async {
                      if (currentUser == null) return;
                      await ref.read(postServiceProvider).toggleCommentLike(comment.$id, currentUser.$id);
                      // Realtime çalıştığı için invalidate etmeye gerek yok ama hızlı tepki için eklenebilir
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        size: 16,
                        color: isLiked ? Colors.red : Colors.grey,
                      ),
                    ),
                  ),
                  if (likesCount > 0)
                    Text('$likesCount', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
              // 🗑️ SİLME BUTONU
              if (currentUser?.$id == userId)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                  onPressed: () => _deleteComment(context, ref),
                ),
            ],
          ),
        );
      },
    );
  }
}