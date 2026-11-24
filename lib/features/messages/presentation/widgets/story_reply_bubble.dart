import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:appwrite/models.dart' as models;
import '../../../../services/appwrite_service.dart';
import '../../../stories/data/story_service.dart';
import '../../../stories/presentation/pages/story_viewer_page.dart';
import '../../../auth/data/auth_providers.dart';

class StoryReplyBubble extends ConsumerWidget {
  final models.Document message;
  final bool isMe;

  const StoryReplyBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fileId = message.data['fileId'];
    final content = message.data['content'] ?? '';
    final imageUrl = fileId != null ? AppwriteService.getFilePreviewUrl(fileId) : null;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF2A2A2A) : const Color(0xFF3A3A3A), // Koyu tema renkleri
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Story Reply Card (Tıklanabilir Alan)
            GestureDetector(
              onTap: () => _openOriginalStory(context, ref, fileId),
              child: Container(
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border(left: BorderSide(color: Colors.purple.shade400, width: 3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 📸 Küçük Dikey Thumbnail
                    if (imageUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          height: 50, // Instagram tarzı küçük yükseklik
                          width: 30,  // Dikey oran (9:16 benzeri)
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(color: Colors.grey[800]),
                          errorWidget: (context, url, error) => const Icon(Icons.broken_image, color: Colors.white, size: 16),
                        ),
                      ),
                    
                    const SizedBox(width: 10),
                    
                    // 📝 "Story'e yanıt" Yazısı
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isMe ? "Hikayesine yanıt verdin" : "Hikayene yanıt verdi",
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 2. Mesaj Metni (Balonun Altında)
            if (content.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: Text(
                  content,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openOriginalStory(BuildContext context, WidgetRef ref, String? mediaId) async {
    if (mediaId == null) return;

    try {
      // StoryService üzerinden orijinal hikayeyi bul
      final storyDoc = await ref.read(storyServiceProvider).getStoryByMediaId(mediaId);

      if (storyDoc != null) {
        // Hikaye bulunduysa Viewer'ı aç
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StoryViewerPage(
                // Tek bir hikaye için feedData oluşturuyoruz
                feedData: [{
                  'userId': storyDoc.data['userId'],
                  'stories': [storyDoc],
                  'isMe': false, // Viewer içinde kontrol ediliyor zaten
                }],
                initialUserIndex: 0,
              ),
            ),
          );
        }
      } else {
        // Hikaye silinmiş veya süresi dolmuşsa
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bu hikaye artık mevcut değil.')),
          );
        }
      }
    } catch (e) {
      debugPrint('Hikaye açma hatası: $e');
    }
  }
}
