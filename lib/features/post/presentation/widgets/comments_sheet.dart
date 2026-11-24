import 'dart:async';
import 'package:appwrite/models.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/config/appwrite_config.dart';
import '../../../../services/appwrite_service.dart';
import '../../../../services/image_upload_service.dart';
import '../../../../services/post_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../follow/data/follow_service.dart';
import '../../../home/presentation/widgets/mention_text.dart';
import '../../data/providers/post_providers.dart';
import '../../../home/data/feed_provider.dart';

class CommentsSheet extends ConsumerStatefulWidget {
  final String postId;
  final String postOwnerId;

  const CommentsSheet({
    super.key,
    required this.postId,
    required this.postOwnerId,
  });

  @override
  ConsumerState<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<CommentsSheet> {
  final TextEditingController _commentController = TextEditingController();
  bool _isSending = false;

  // Etiketleme değişkenleri
  List<Document> _mentionSuggestions = [];
  bool _showMentions = false;
  String? _currentMentionQuery;
  Timer? _debounce;

  @override
  void dispose() {
    _commentController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // --- MENTION MANTIĞI ---
  void _onTextChanged(String text) {
    final selection = _commentController.selection;
    if (selection.baseOffset < 0) return;

    final textBeforeCursor = text.substring(0, selection.baseOffset);
    final words = textBeforeCursor.split(RegExp(r'\s+'));
    final lastWord = words.isNotEmpty ? words.last : '';

    if (lastWord.startsWith('@')) {
      final query = lastWord.substring(1).toLowerCase();
      
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), () {
        _searchUsers(query);
      });

      setState(() {
        _currentMentionQuery = query;
        _showMentions = true;
      });
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
        query: query,
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

  // --- YORUM GÖNDERME ---
  Future<void> _sendComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) return;

    setState(() => _isSending = true);

    try {
      await ref.read(postServiceProvider).createComment(
        widget.postId,
        currentUser.$id,
        content,
      );

      _commentController.clear();
      // Listeleri yenile
      ref.invalidate(postCommentsProvider(widget.postId));
      ref.invalidate(postDetailsProvider(widget.postId));
      
      // 🔄 SENKRONİZASYON: Ana akış ve Reels akışındaki yorum sayısını güncelle
      final updatedPost = await ref.read(postServiceProvider).getPost(widget.postId);
      if (mounted) {
        ref.read(feedPostsProvider.notifier).updateSpecificPost(updatedPost);
        ref.read(reelsPostsProvider.notifier).updateSpecificPost(updatedPost);
      }
      
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final commentsAsync = ref.watch(postCommentsProvider(widget.postId));
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85, // Ekranın %85'i
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // --- HEADER ---
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
            ),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          // --- YORUM LİSTESİ ---
          Expanded(
            child: commentsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Yorumlar yüklenemedi: $e')),
              data: (comments) {
                if (comments.isEmpty) {
                  return const Center(
                    child: Text('Henüz yorum yok. İlk yorumu sen yap!', style: TextStyle(color: Colors.grey)),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: comments.length,
                  separatorBuilder: (context, index) => const Divider(height: 24),
                  itemBuilder: (context, index) {
                    return _SheetCommentItem(comment: comments[index], postId: widget.postId);
                  },
                );
              },
            ),
          ),

          // --- ÖNERİ LİSTESİ (Input'un üstünde) ---
          if (_showMentions && _mentionSuggestions.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2))),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))],
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _mentionSuggestions.length,
                itemBuilder: (context, index) {
                  final user = _mentionSuggestions[index].data;
                  final photoId = user['photoId'] ?? user['profileImageUrl'];
                  
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundImage: (photoId != null && photoId.isNotEmpty)
                          ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId)) 
                          : null,
                      child: (photoId == null || photoId.isEmpty) ? Text(user['displayName'][0].toUpperCase()) : null,
                    ),
                    title: Text(user['displayName']),
                    subtitle: Text('@${user['username']}'),
                    onTap: () => _selectMention(user['username']),
                  );
                },
              ),
            ),

          // --- INPUT ALANI ---
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + viewInsets.bottom),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2))),
            ),
            child: Row(
              children: [
                Consumer(builder: (context, ref, _) {
                  final user = ref.watch(currentUserProfileProvider).value;
                  final photoId = user?['photoId'] ?? user?['profileImageUrl'];
                  return CircleAvatar(
                    radius: 18,
                    backgroundImage: (photoId != null && photoId.isNotEmpty)
                        ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId)) 
                        : null,
                    child: (photoId == null || photoId.isEmpty) ? const Icon(Icons.person, size: 20) : null,
                  );
                }),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    onChanged: _onTextChanged,
                    decoration: InputDecoration(
                      hintText: 'Yanıtını gönder...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).scaffoldBackgroundColor,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
        ],
      ),
    );
  }
}

class _SheetCommentItem extends ConsumerWidget {
  final Document comment;
  final String postId;
  const _SheetCommentItem({required this.comment, required this.postId});

  Future<void> _deleteComment(BuildContext context, WidgetRef ref) async {
    // Silme onayı ve işlemi
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yorumu Sil'),
        content: const Text('Bu yorumu silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil', style: TextStyle(color: Colors.red))),
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

      // Post yorum sayısını güncelle (Basit azaltma)
      // Not: Daha sağlam yapı için Cloud Function önerilir ama burada client-side yapıyoruz.
      ref.invalidate(postCommentsProvider(postId));
      ref.invalidate(postDetailsProvider(postId));
      
      // 🔄 SENKRONİZASYON: Silme işleminden sonra sayaçları güncelle
      final updatedPost = await ref.read(postServiceProvider).getPost(postId);
      if (context.mounted) {
        ref.read(feedPostsProvider.notifier).updateSpecificPost(updatedPost);
        ref.read(reelsPostsProvider.notifier).updateSpecificPost(updatedPost);
      }
      
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
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

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: (photoId != null && photoId.isNotEmpty)
                  ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId)) 
                  : null,
              child: (photoId == null || photoId.isEmpty) ? Text(name[0].toUpperCase()) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(width: 6),
                      Text('@$username', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      const Spacer(),
                      Text(DateFormat('d MMM').format(createdAt), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  MentionText(
                    text: content,
                    style: const TextStyle(fontSize: 14),
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
            // 🗑️ SİLME BUTONU (Kendi yorumuysa)
            if (currentUser?.$id == userId)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                onPressed: () => _deleteComment(context, ref),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        );
      },
    );
  }
}