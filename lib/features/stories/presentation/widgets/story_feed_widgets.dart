import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:appwrite/models.dart' as models;
import '../../data/story_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../follow/data/follow_service.dart';
import '../pages/story_viewer_page.dart';
import '../pages/story_camera_page.dart';
import '../../../../services/appwrite_service.dart';

final storyFeedDataProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final currentUser = ref.watch(currentUserProvider).value;
  if (currentUser == null) return [];

  // Takip edilenleri ve kendi ID'mizi al
  final followingIds = await ref.watch(followServiceProvider).getFollowingIds(currentUser.$id);
  final allIds = [currentUser.$id, ...followingIds];

  // İlgili kullanıcıların hikayelerini çek
  final stories = await ref.read(storyServiceProvider).getStoriesFeed(allIds);

  // Hikayeleri kullanıcı ID'sine göre grupla
  final Map<String, List<models.Document>> groupedStories = {};
  for (var story in stories) {
    final uid = story.data['userId'];
    if (!groupedStories.containsKey(uid)) {
      groupedStories[uid] = [];
    }
    groupedStories[uid]!.add(story);
  }

  // Kendi hikayemiz olmasa bile "Hikaye Ekle" butonu için kendimizi listeye dahil et
  if (!groupedStories.containsKey(currentUser.$id)) {
    groupedStories[currentUser.$id] = [];
  }

  // Önce ben, sonra diğerleri şeklinde sırala
  final sortedUserIds = groupedStories.keys.toList()
    ..sort((a, b) => a == currentUser.$id ? -1 : 1);

  // UI'da kullanılacak veriyi hazırla
  return sortedUserIds.map((userId) => {'userId': userId, 'stories': groupedStories[userId]!, 'isMe': userId == currentUser.$id}).toList();
});

class StoryFeedWidget extends ConsumerWidget {
  const StoryFeedWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider).value;
    if (currentUser == null) return const SizedBox.shrink();

    final feedAsync = ref.watch(storyFeedDataProvider);

    return SizedBox(
      height: 100, // 🟢 Yükseklik azaltıldı (110 -> 100)
      child: feedAsync.when(
        data: (feedData) => ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          itemCount: feedData.length,
          itemBuilder: (context, index) {
            final item = feedData[index];
            return _buildStoryBubble(
              context,
              item['userId'],
              item['stories'],
              item['isMe'],
              ref,
              feedData, // Tüm listeyi gönder
              index,    // Tıklanan index
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hikayeler yüklenemedi: $e')),
      ),
    );
  }

  Widget _buildStoryBubble(
    BuildContext context, 
    String userId, 
    List<models.Document> stories, 
    bool isMe, 
    WidgetRef ref,
    List<Map<String, dynamic>> allFeedData,
    int index,
  ) {
    final hasStory = stories.isNotEmpty;
    
    return Consumer(
      builder: (context, ref, _) {
        final userAsync = ref.watch(userProfileProvider(userId));
        return userAsync.when(
          data: (user) {
            final name = isMe ? "Hikayen" : (user?['displayName'] ?? 'Kullanıcı');
            final photoId = user?['photoId'] ?? user?['profileImageUrl'];
            final imageUrl = photoId != null ? AppwriteService.getFileViewUrl(photoId) : null;

            return GestureDetector(
              onTap: () {
                if (isMe && !hasStory) {
                  // Hikaye yoksa kamera aç
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const StoryCameraPage()));
                } else if (hasStory) {
                  // Hikaye varsa izle
                  Navigator.push(context, MaterialPageRoute(builder: (_) => StoryViewerPage(
                    feedData: allFeedData,
                    initialUserIndex: index,
                  )));
                }
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  children: [
                    Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: hasStory ? Border.all(color: Colors.purple, width: 2.5) : Border.all(color: Colors.grey[300]!, width: 1),
                          ),
                          child: CircleAvatar(
                            radius: 28, // 🟢 Avatar boyutu biraz küçültüldü (30 -> 28)
                            backgroundColor: Colors.grey[200],
                            backgroundImage: imageUrl != null ? CachedNetworkImageProvider(imageUrl) : null,
                            child: imageUrl == null ? const Icon(Icons.person, color: Colors.grey) : null,
                          ),
                        ),
                        if (isMe && !hasStory)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.blue, 
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(Icons.add, size: 12, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            );
          },
          loading: () => const SizedBox(width: 70, child: Center(child: CircularProgressIndicator())),
          error: (_,__) => const SizedBox.shrink(),
        );
      },
    );
  }
}
