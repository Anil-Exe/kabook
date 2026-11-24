import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:appwrite/appwrite.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/feed_provider.dart';
import '../../../post/presentation/widgets/post_card.dart';
import '../../../post/data/providers/post_providers.dart';
import '../../../block/data/block_service.dart';
import '../../../follow/data/follow_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../../services/appwrite_service.dart';
import '../../../stories/presentation/pages/story_camera_page.dart';
import '../../../stories/presentation/widgets/story_feed_widgets.dart';
import '../../../../core/config/appwrite_config.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final ScrollController _scrollController = ScrollController();
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    // ♾️ Sonsuz Kaydırma Dinleyicisi
    _scrollController.addListener(_onScroll);
    _pageController = PageController(initialPage: 1); // 0: Kamera, 1: Ana Sayfa
  }

  void _onScroll() {
    // 🟢 İSTEK: Son 3 gönderiye gelince yenileri yüklensin (Ortalama bir post 400px desek 1200px)
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 1200) {
      ref.read(feedPostsProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _pageController,
      children: [
        const StoryCameraPage(),
        _buildHomeFeed(),
      ],
    );
  }

  Widget _buildHomeFeed() {
    final filterState = ref.watch(feedFilterProvider);
    final postsAsync = ref.watch(feedPostsProvider);

    return Scaffold(
      drawer: const Drawer(
        child: Center(
          child: Text('Menü'),
        ),
      ),
      body: NestedScrollView(
        floatHeaderSlivers: true, // 🟢 Aşağı kaydırınca gizle, yukarı kaydırınca getir
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          // 1. Story Feed (Kaybolan kısım) - En üste alındı
          const SliverToBoxAdapter(
            child: SizedBox(
              height: 100, // 🟢 Yükseklik azaltıldı (115 -> 100)
              child: StoryFeedWidget(),
            ),
          ),

          // 2. Filtreler (Yapışkan kısım) - Story'nin altına alındı
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyHeaderDelegate(
              minHeight: 95,
              maxHeight: 95,
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Column(
                  children: [
                    // 1️⃣ ANA FİLTRE
                    Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.withOpacity(0.1)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _MainFilterTab(
                              label: 'Üniversiteniz',
                              isSelected: filterState.isMyUniversity,
                              onTap: () => ref.read(feedFilterProvider.notifier).state = 
                                  filterState.copyWith(isMyUniversity: true),
                            ),
                          ),
                          Expanded(
                            child: _MainFilterTab(
                              label: 'Diğer Üniversiteler',
                              isSelected: !filterState.isMyUniversity,
                              onTap: () => ref.read(feedFilterProvider.notifier).state = 
                                  filterState.copyWith(isMyUniversity: false),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // 2️⃣ ALT FİLTRE
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                      child: Row(
                        children: [
                          _SubFilterChip(
                            label: 'Takip Edilenler',
                            isSelected: filterState.isFollowingOnly,
                            onTap: () => ref.read(feedFilterProvider.notifier).state = 
                                filterState.copyWith(isFollowingOnly: true),
                          ),
                          const SizedBox(width: 12),
                          _SubFilterChip(
                            label: 'Herkes',
                            isSelected: !filterState.isFollowingOnly,
                            onTap: () => ref.read(feedFilterProvider.notifier).state = 
                                filterState.copyWith(isFollowingOnly: false),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: RefreshIndicator(
              color: AppColors.primaryGreen,
              onRefresh: () async {
                // Filtre provider'ını invalidate etmeye gerek yok, posts değişince o da çalışır
                return ref.read(feedPostsProvider.notifier).refresh();
              },
              child: postsAsync.when(
                data: (posts) {
                  // Eğer liste boşsa
                  final bool possiblyHasMore = posts.length >= 10 && posts.length % 10 == 0;
                  
                  if (posts.isEmpty && !possiblyHasMore) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(32),
                      children: [
                        const SizedBox(height: 40),
                        Icon(
                          Icons.feed_outlined, 
                          size: 64, 
                          color: Colors.grey.withOpacity(0.3)
                        ),
                        const SizedBox(height: 16),
                        const Center(
                          child: Text(
                            'Bu filtreye uygun gönderi bulunamadı.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    );
                  }

                  final int itemCount = possiblyHasMore ? posts.length + 1 : posts.length;

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: itemCount,
                    itemBuilder: (context, index) {
                      if (index == posts.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16.0),
                          child: Center(
                            child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryGreen))
                          ),
                        );
                      }
                      return PostCard(post: posts[index]);
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
                error: (e, _) => Center(child: Text('Hata: $e')),
              ),
            ),
      ),
    );
  }
}

/// 📌 Yapışkan Header Delegate
class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double minHeight;
  final double maxHeight;
  final Widget child;

  _StickyHeaderDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });

  @override
  double get minExtent => minHeight;
  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(_StickyHeaderDelegate oldDelegate) {
    return maxHeight != oldDelegate.maxHeight ||
        minHeight != oldDelegate.minHeight ||
        child != oldDelegate.child;
  }
}

/// 🎨 Ana Sekme Tasarımı (Altı Çizgili)
class _MainFilterTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _MainFilterTab({
    required this.label, 
    required this.isSelected, 
    required this.onTap
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10), // 🟢 Boşluk azaltıldı (16 -> 10)
        decoration: BoxDecoration(
          border: isSelected 
              ? const Border(bottom: BorderSide(color: AppColors.primaryGreen, width: 3))
              : const Border(bottom: BorderSide(color: Colors.transparent, width: 3)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? AppColors.primaryGreen : Colors.grey,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

/// 🎨 Alt Filtre Çip Tasarımı (Yuvarlak Buton)
class _SubFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SubFilterChip({
    required this.label, 
    required this.isSelected, 
    required this.onTap
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primaryGreen : Colors.grey.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[600],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}