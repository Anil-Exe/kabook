import '../../../follow/presentation/widgets/follow_button.dart';
import '../../../follow/presentation/pages/follow_user_list_page.dart';
import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../services/auth_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../post/presentation/widgets/post_card.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../stories/data/story_service.dart';
import '../../../stories/presentation/pages/story_camera_page.dart';
import '../../../stories/presentation/pages/story_viewer_page.dart';
import '../../../post/data/providers/post_providers.dart';
import '../../../../services/image_upload_service.dart';
import '../../../follow/data/follow_service.dart';
import 'user_events_page.dart';
import '../../../block/data/block_service.dart'; // 🆕 Block Service Import
import '../../../messages/data/message_providers.dart'; // 🆕 Message Providers Import

// Real-time sayaçlar için providerlar
final followersCountProvider = FutureProvider.family<int, String>((ref, userId) async {
  final service = ref.read(followServiceProvider);
  return service.getFollowersCount(userId);
});

final followingCountProvider = FutureProvider.family<int, String>((ref, userId) async {
  final service = ref.read(followServiceProvider);
  return service.getFollowingCount(userId);
});

// Kullanıcının hikayelerini getiren provider
final userStoriesProvider = FutureProvider.family<List<models.Document>, String>((ref, userId) async {
  return ref.read(storyServiceProvider).getMyStories(userId);
});

class ProfilePage extends ConsumerWidget {
  final String userId;
  const ProfilePage({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProvider(userId));
    final followersAsync = ref.watch(followersCountProvider(userId));
    final userStoriesAsync = ref.watch(userStoriesProvider(userId)); // Hikayeleri çek
    final followingAsync = ref.watch(followingCountProvider(userId));
    final canViewAsync = ref.watch(canViewProfileProvider(userId));
    final currentUser = ref.watch(currentUserProvider).value;
    final isOwnProfile = currentUser?.$id == userId;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // 🚫 Engelleme Durumu Kontrolü
    final blockStatusAsync = currentUser != null 
        ? ref.watch(blockStatusProvider('${currentUser.$id}|$userId'))
        : const AsyncValue.data([false, false]); // Giriş yapmamışsa engelsiz varsay

    //  Realtime Takip Güncellemeleri
    ref.listen(followRealtimeProvider, (_, next) {
      next.whenData((event) {
        final payload = event.payload;
        if (payload.isNotEmpty) {
          // Eğer gelen event (takip etme/bırakma) bu profili ilgilendiriyorsa sayaçları yenile
          if (payload['followerId'] == userId || payload['followingId'] == userId) {
            ref.invalidate(followersCountProvider(userId));
            ref.invalidate(followingCountProvider(userId));
          }
        }
      });
    });

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Profil'),
          actions: [
            if (isOwnProfile)
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () {
                  context.push('/settings'); // Router'da tanımlı olmalı
                },
              ),
            
            // 🚫 Başkasının profili ise Engelleme Menüsü
            if (!isOwnProfile && currentUser != null)
              blockStatusAsync.when(
                data: (status) {
                  final didIBlock = status[0];
                  // Eğer ben engellediysem menüde "Engeli Kaldır" yazar
                  return PopupMenuButton<String>(
                    onSelected: (value) => _handleBlockAction(context, ref, value, currentUser.$id, didIBlock),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: didIBlock ? 'unblock' : 'block',
                        child: Text(
                          didIBlock ? 'Engeli Kaldır' : 'Engelle',
                          style: TextStyle(color: didIBlock ? null : Colors.red),
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
          ],
        ),
        body: userAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Hata: $e')),
          data: (userDoc) {
            // 🚫 Engelleme Kontrolü (UI Kararı)
            return blockStatusAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Center(child: Text('Bir hata oluştu')),
              data: (status) {
                final didIBlock = status[0];
                final didTheyBlock = status[1];

                // 1. Eğer BEN engellediysem
                if (didIBlock) {
                  return _buildBlockedView(context, "Bu kullanıcıyı engelledin", "İçerikleri görmek için engeli kaldır.");
                }

                // 2. Eğer O beni engellediyse
                if (didTheyBlock) {
                  return _buildBlockedView(context, "Kullanıcı Bulunamadı", "Profil görüntülenemiyor.");
                }

                // 3. Engel yoksa normal akış
                return _buildNormalProfile(context, ref, userDoc, canViewAsync, followersAsync, followingAsync, userStoriesAsync, isOwnProfile, isDark);
              },
            );
          },
        ),
      ),
    );
  }

  // Mevcut profil içeriğini buraya taşıdık (Refactoring)
  Widget _buildNormalProfile(BuildContext context, WidgetRef ref, dynamic userDoc, AsyncValue<bool> canViewAsync, AsyncValue<int> followersAsync, AsyncValue<int> followingAsync, AsyncValue<List<models.Document>> userStoriesAsync, bool isOwnProfile, bool isDark) {
            final data = userDoc.data;
            final postsCount = data['postsCount'] ?? 0;
            return canViewAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Hata: $e')),
              data: (canView) {
                return NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      // 🖼️ Profil Fotoğrafı
                      GestureDetector(
                        onTap: () {
                          // Hikaye varsa aç
                          userStoriesAsync.whenData((stories) {
                            if (stories.isNotEmpty) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StoryViewerPage(
                                    feedData: [{'userId': userId, 'stories': stories}], // Tek kullanıcı modu gibi davranır
                                    initialUserIndex: 0,
                                  ),
                                ),
                              );
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: userStoriesAsync.hasValue && userStoriesAsync.value!.isNotEmpty
                                ? Border.all(color: Colors.purple, width: 3) // Hikaye varsa Mor
                                : Border.all(
                                    color: AppColors.brandGreen.withOpacity(0.5),
                                    width: 2,
                                  ),
                          ),
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: AppColors.brandGreen.withOpacity(0.1),
                            backgroundImage: data['photoId'] != null
                                ? CachedNetworkImageProvider(
                                    MediaService.getFileUrl(data['photoId']))
                                : null,
                            child: data['photoId'] == null
                                ? Text(
                                    (data['displayName'] as String).isNotEmpty
                                        ? (data['displayName'] as String)[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(fontSize: 40, color: AppColors.brandGreen),
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // 👤 İsim & Rol
                      Text(
                        data['displayName'],
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.brandGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          data['role'] ?? 'Öğrenci',
                          style: const TextStyle(
                            color: AppColors.brandGreen,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      
                      // 📝 Bio
                      if (data['bio'] != null && (data['bio'] as String).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
                          child: Text(
                            data['bio'],
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: 1.4,
                              color: isDark ? Colors.grey[300] : Colors.grey[700],
                            ),
                          ),
                        ),

                      const SizedBox(height: 24),

                      // 📊 İstatistikler
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStatItem(context, 'Gönderi', '$postsCount'),
                          _buildStatItem(
                            context,
                            'Takipçi', 
                            followersAsync.when(
                              data: (d) => '$d',
                              loading: () => '-',
                              error: (_, __) => '0',
                            ),
                            onTap: canView ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FollowUserListPage(userId: userId, type: 'followers'),
                                ),
                              );
                            } : null,
                          ),
                          _buildStatItem(
                            context,
                            'Takip Edilen',
                            followingAsync.when(
                              data: (d) => '$d',
                              loading: () => '-',
                              error: (_, __) => '0',
                            ),
                            onTap: canView ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FollowUserListPage(userId: userId, type: 'following'),
                                ),
                              );
                            } : null,
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // 🔘 Aksiyon Butonları
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            if (!isOwnProfile) ...[
                              Expanded(child: FollowButton(targetUserId: userId)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () async {
                                    final currentUser = ref.read(currentUserProvider).value;
                                    if (currentUser == null) return;

                                    try {
                                      final chatDoc = await ref.read(messageServiceProvider).getOrCreateDirectChat(
                                        currentUserId: currentUser.$id,
                                        targetUserId: userId,
                                      );
                                      
                                      if (context.mounted) {
                                        context.push('/chat/${chatDoc.$id}', extra: data['displayName']);
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
                                      }
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                                    foregroundColor: isDark ? Colors.white : Colors.black,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: const Text('Mesaj', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                            
                            if (isOwnProfile) ...[
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => context.push('/edit-profile'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    side: BorderSide(color: Colors.grey.withOpacity(0.3)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    foregroundColor: isDark ? Colors.white : Colors.black87,
                                  ),
                                  child: const Text('Düzenle', style: TextStyle(fontWeight: FontWeight.w600)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => UserEventsPage(userId: userId, viewType: 'joined'),
                                      ),
                                    );
                                  },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                                    side: BorderSide(color: Colors.grey.withOpacity(0.3)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    foregroundColor: isDark ? Colors.white : Colors.black87,
                                  ),
                                  child: const Text('Katıldığım', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => UserEventsPage(userId: userId, viewType: 'created'),
                                      ),
                                    );
                                  },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                                    side: BorderSide(color: Colors.grey.withOpacity(0.3)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    foregroundColor: isDark ? Colors.white : Colors.black87,
                                  ),
                                  child: const Text('Oluşturduğum', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // 🎓 Akademik Bilgiler Kartı
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F7FA),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(
                            children: [
                              _InfoRow(icon: Icons.school_outlined, text: data['university'] ?? 'Üniversite Yok'),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Divider(height: 1, color: Colors.grey.withOpacity(0.1)),
                              ),
                              _InfoRow(icon: Icons.account_balance_outlined, text: data['faculty'] ?? 'Fakülte Yok'),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Divider(height: 1, color: Colors.grey.withOpacity(0.1)),
                              ),
                              _InfoRow(icon: Icons.menu_book_outlined, text: data['department'] ?? 'Bölüm Yok'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
                if (canView)
                SliverPersistentHeader(
                  delegate: _SliverAppBarDelegate(
                    TabBar(
                      tabs: const [
                        Tab(text: 'Gönderiler'),
                        Tab(text: 'Repostlar'),
                      ],
                      indicatorColor: AppColors.brandGreen,
                      labelColor: AppColors.brandGreen,
                      unselectedLabelColor: Colors.grey,
                      indicatorSize: TabBarIndicatorSize.label,
                      dividerColor: Colors.transparent,
                    ),
                  ),
                  pinned: true,
                ),
              ],
              body: canView 
                  ? TabBarView(
                      children: [
                        _UserPostsList(userId: userId),
                        _UserRepostsList(userId: userId),
                      ],
                    )
                  : _buildPrivateView(context),
            );
          },
        );
  }
  
  Widget _buildPrivateView(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.shade300, width: 2),
          ),
          child: Icon(Icons.lock_outline, size: 48, color: Colors.grey.shade800),
        ),
        const SizedBox(height: 24),
        Text(
          'Bu Hesap Gizli',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Fotoğraflarını ve videolarını görmek için takip et.',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      ],
    );
  }

  // 🚫 Engellenmiş Profil Görünümü
  Widget _buildBlockedView(BuildContext context, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.block, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ⚡ Engelleme Aksiyonu
  Future<void> _handleBlockAction(BuildContext context, WidgetRef ref, String action, String currentUserId, bool isBlocked) async {
    final blockService = ref.read(blockServiceProvider);
    
    if (action == 'block') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Kullanıcıyı Engelle'),
          content: const Text('Bu kullanıcıyı engellemek istediğine emin misin? Birbirinizin gönderilerini göremeyecek ve mesajlaşamayacaksınız.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Engelle'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await blockService.blockUser(currentUserId: currentUserId, targetUserId: userId);
        ref.invalidate(blockStatusProvider); // UI'ı yenile
        ref.invalidate(followersCountProvider(userId)); // Sayaçları yenile
        ref.invalidate(followingCountProvider(userId));
      }
    } else if (action == 'unblock') {
      await blockService.unblockUser(currentUserId: currentUserId, targetUserId: userId);
      ref.invalidate(blockStatusProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Engel kaldırıldı')));
      }
    }
  }

  Widget _buildStatItem(BuildContext context, String label, String count, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            Text(
              count,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
      ],
    );
  }
}

class _UserPostsList extends ConsumerWidget {
  final String userId;
  const _UserPostsList({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(userPostsProvider(userId));
    return postsAsync.when(      
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
      error: (e, _) => Center(child: Text('Gönderiler yüklenemedi: $e')),
      data: (posts) {
        if (posts.isEmpty) {
          return const Center(child: Text("Henüz gönderi yok.", style: TextStyle(color: Colors.grey)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: posts.length,
          itemBuilder: (context, index) {
            final post = posts[index];
            return PostCard(key: ValueKey(post.id), post: post);
          },
        );
      },
    );
  }
}

class _UserRepostsList extends ConsumerWidget {
  final String userId;
  const _UserRepostsList({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(userRepostsProvider(userId));
    return postsAsync.when(      
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
      error: (e, _) => Center(child: Text('Gönderiler yüklenemedi: $e')),
      data: (posts) {
        if (posts.isEmpty) {
          return const Center(child: Text("Henüz repost yok.", style: TextStyle(color: Colors.grey)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: posts.length,
          itemBuilder: (context, index) {
            final post = posts[index];
            return PostCard(key: ValueKey(post.id), post: post);
          },
        );
      },
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;
  _SliverAppBarDelegate(this._tabBar);
  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: Theme.of(context).scaffoldBackgroundColor, child: _tabBar);
  }
  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}