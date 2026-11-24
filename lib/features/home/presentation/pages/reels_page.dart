import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:appwrite/models.dart' as models;

import '../../../../core/theme/app_theme.dart';
import '../../../../services/image_upload_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../post/data/providers/post_providers.dart';
import '../../data/feed_provider.dart';
import '../../../../models/post_model.dart';
import '../../../post/presentation/widgets/post_card.dart';
import '../../../post/presentation/widgets/comments_sheet.dart';
import '../../../post/presentation/widgets/share_post_sheet.dart';
import '../../../../services/post_service.dart';
import '../../../block/data/block_service.dart';
import '../../../follow/data/follow_service.dart';

class ReelsPage extends ConsumerStatefulWidget {
  final String? initialPostId; // 🟢 EKLENDİ: Başlangıç videosu ID'si
  const ReelsPage({super.key, this.initialPostId});

  @override
  ConsumerState<ReelsPage> createState() => _ReelsPageState();
}

class _ReelsPageState extends ConsumerState<ReelsPage> {
  PageController? _horizontalController;
  PageController? _pageController; // 🟢 Değişiklik: Nullable yaptık
  int _currentIndex = 0;
  DateTime? _startTime; // İzleme başlangıç zamanı
  String? _currentPostId; // Şu an izlenen post ID
  
  Post? _fetchedInitialPost;
  bool _isFetchingInitialPost = false;
  String? _localInitialPostId;
  bool _isResolvingInitialFilter = false; // 🟢 Filtrenin tespit edildiğini belirten bayrak

  @override
  void initState() {
    super.initState();
    _localInitialPostId = widget.initialPostId;
    if (_localInitialPostId != null) {
      _isResolvingInitialFilter = true;
      _fetchInitialPost();
    }
  }

  Future<void> _fetchInitialPost() async {
    setState(() => _isFetchingInitialPost = true);
    try {
      final post = await ref.read(postServiceProvider).getPost(_localInitialPostId!);
      
      // 🟢 Videonun hangi filtreye ait olduğunu tespit et ve o filtreye geç
      try {
        final userProfile = await ref.read(currentUserProfileProvider.future);
        final myUniversity = userProfile?['university'] as String?;
        
        if (mounted) {
          bool isMyUni = true; // Varsayılan olarak kendi üniversitemiz gibi varsayalım
          if (myUniversity != null && myUniversity.isNotEmpty && post.university != null && post.university!.isNotEmpty) {
            isMyUni = (myUniversity == post.university);
          }
          
          // State'i otomatik olarak hedeflenen filtreye ayarla
          ref.read(reelsFilterSettingsProvider.notifier).state = FeedFilterState(
            isMyUniversity: isMyUni,
            isFollowingOnly: false, // Genel akışlarda açılması daha mantıklı
          );
        }
      } catch (e) {
        debugPrint("Filtre belirleme hatası: $e");
      }

      if (mounted) {
        setState(() {
          _fetchedInitialPost = post;
          _isFetchingInitialPost = false;
          _isResolvingInitialFilter = false; // İşlem bitti
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFetchingInitialPost = false;
          _isResolvingInitialFilter = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _horizontalController?.dispose();
    _pageController?.dispose();
    super.dispose();
  }

  // 📊 ANALYTICS: Sayfa değiştiğinde önceki videonun verisini kaydet
  void _onPageChanged(int index, List<Post> posts) {
    final now = DateTime.now();
    
    // 1. Önceki videonun analizini kaydet (Eğer varsa)
    if (_startTime != null && _currentPostId != null) {
      final duration = now.difference(_startTime!);
      final seconds = duration.inSeconds;
      
      // Servise logla
      final postService = ref.read(postServiceProvider);
      final currentUser = ref.read(currentUserProvider).value;
      
      if (currentUser != null) {
        // View Duration
        postService.logEvent(
          userId: currentUser.$id,
          postId: _currentPostId!,
          eventType: 'view',
          metadata: {'duration_ms': duration.inMilliseconds},
        );

        // Skip Logic (İlk 2 saniyede geçildiyse)
        if (seconds < 2) {
          postService.logEvent(
            userId: currentUser.$id,
            postId: _currentPostId!,
            eventType: 'skip', // Algoritmada negatif puan
          );
        }
      }
    }

    // 2. Yeni videonun takibini başlat
    setState(() {
      _currentIndex = index;
      _startTime = now;
      _currentPostId = posts[index].id;
    });

    // ♾️ Infinite Scroll: Son 3 videoya gelince yenilerini yükle
    if (index >= posts.length - 3) {
      ref.read(reelsPostsProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final postsAsync = ref.watch(reelsPostsProvider);
    final filterState = ref.watch(reelsFilterSettingsProvider);
    
    final currentHorizontalIndex = filterState.isFollowingOnly 
        ? 2 
        : (!filterState.isMyUniversity ? 1 : 0);

    if (_horizontalController == null) {
      _horizontalController = PageController(initialPage: currentHorizontalIndex);
    }

    ref.listen<FeedFilterState>(reelsFilterSettingsProvider, (prev, next) {
      final newIndex = next.isFollowingOnly ? 2 : (!next.isMyUniversity ? 1 : 0);
      if (_horizontalController?.hasClients == true && _horizontalController!.page?.round() != newIndex) {
        setState(() {
          if (!_isResolvingInitialFilter) {
            _localInitialPostId = null; // Filtre (sekme) SADECE MANUEL değişirse, videoyu aradan çıkar
          }
          _pageController?.dispose();
          _pageController = null;
          _currentIndex = 0;
        });
        _horizontalController!.animateToPage(
          newIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });

    // 🔝 Yukarı Kaydırma Dinleyicisi
    ref.listen(homeScrollToTopProvider, (previous, next) {
      if (next != null && _pageController != null && _pageController!.hasClients) {
        _pageController!.animateToPage(0, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. YATAY KAYDIRILABİLİR SEKMELER (VİDEO LİSTESİ)
          PageView.builder(
            controller: _horizontalController,
            onPageChanged: (index) {
              final currentState = ref.read(reelsFilterSettingsProvider);
              final currentIndex = currentState.isFollowingOnly ? 2 : (!currentState.isMyUniversity ? 1 : 0);
              
              if (currentIndex != index) {
                setState(() {
                  _localInitialPostId = null; // Elle yana kaydırıldığında da videoyu aradan çıkar
                  _pageController?.dispose();
                  _pageController = null;
                  _currentIndex = 0;
                });
                
                final notifier = ref.read(reelsFilterSettingsProvider.notifier);
                if (index == 0) notifier.state = const FeedFilterState(isMyUniversity: true, isFollowingOnly: false);
                if (index == 1) notifier.state = const FeedFilterState(isMyUniversity: false, isFollowingOnly: false);
                if (index == 2) notifier.state = const FeedFilterState(isMyUniversity: false, isFollowingOnly: true);
              }
            },
            itemCount: 3,
            itemBuilder: (context, index) {
              if (index != currentHorizontalIndex) {
                return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
              }
              return _buildReelsFeed(postsAsync);
            },
          ),

          // 🔝 ÜST FİLTRELER (Overlay)
          Positioned(
            top: 50,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ReelsFilterText(
                  text: 'Üniversiteniz',
                  isSelected: currentHorizontalIndex == 0,
                  onTap: () => ref.read(reelsFilterSettingsProvider.notifier).state = const FeedFilterState(isMyUniversity: true, isFollowingOnly: false),
                ),
                const SizedBox(width: 16),
                Container(width: 1, height: 15, color: Colors.white54),
                const SizedBox(width: 16),
                ReelsFilterText(
                  text: 'Diğer Üniversiteler',
                  isSelected: currentHorizontalIndex == 1,
                  onTap: () => ref.read(reelsFilterSettingsProvider.notifier).state = const FeedFilterState(isMyUniversity: false, isFollowingOnly: false),
                ),
                const SizedBox(width: 16),
                Container(width: 1, height: 15, color: Colors.white54),
                const SizedBox(width: 16),
                ReelsFilterText(
                  text: 'Takip Ettiklerim',
                  isSelected: currentHorizontalIndex == 2,
                  onTap: () => ref.read(reelsFilterSettingsProvider.notifier).state = const FeedFilterState(isMyUniversity: false, isFollowingOnly: true),
                ),
              ],
            ),
          ),

          // 🔙 GERİ BUTONU (Sadece Navigasyon ile gelindiyse)
          if (Navigator.canPop(context))
            Positioned(
              top: 50,
              left: 16,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black26, // Hafif arka plan
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReelsFeed(AsyncValue<List<Post>> postsAsync) {
    if (_isFetchingInitialPost || (postsAsync.isLoading && !postsAsync.hasValue)) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    } else if (postsAsync.hasError && !postsAsync.hasValue) {
      return Center(child: Text('Hata: ${postsAsync.error}', style: const TextStyle(color: Colors.white)));
    } else {
      final posts = postsAsync.value ?? [];
      List<Post> displayPosts = List.from(posts);
      
      // 🟢 Başlangıç videosunu bul veya listeye ekle
      int initialIndex = 0;
      if (_localInitialPostId != null) {
        final foundIndex = displayPosts.indexWhere((p) => p.id == _localInitialPostId);
        if (foundIndex != -1) {
          initialIndex = foundIndex;
        } else if (_fetchedInitialPost != null) {
          displayPosts.insert(0, _fetchedInitialPost!);
          initialIndex = 0;
        }
      }

      if (displayPosts.isEmpty) {
        return const Center(
          child: Text('Henüz video yok.', style: TextStyle(color: Colors.white)),
        );
      }
      
      // Controller henüz oluşturulmadıysa veya index değiştiyse yeniden oluştur
      if (_pageController == null) {
        _pageController = PageController(initialPage: initialIndex);
        _currentIndex = initialIndex;
        _currentPostId = displayPosts[initialIndex].id;
        _startTime = DateTime.now(); // İlk video için sayaç başlat
      }

      // 🔄 REELS YENİLEME (Pull-to-Refresh)
      return RefreshIndicator(
        color: AppColors.primaryGreen,
        backgroundColor: Colors.white,
        onRefresh: () async => ref.read(reelsPostsProvider.notifier).refresh(),
        child: PageView.builder(
          physics: const AlwaysScrollableScrollPhysics(), // Yenileme için gerekli
          controller: _pageController!,
          scrollDirection: Axis.vertical,
          allowImplicitScrolling: true, // 🟢 Performans: Bir sonraki videoyu önceden yükle
          itemCount: displayPosts.length,
          onPageChanged: (index) => _onPageChanged(index, displayPosts),
          itemBuilder: (context, index) {
            return ReelsItem(
              post: displayPosts[index],
              key: ValueKey(displayPosts[index].id),
              isActive: index == _currentIndex, // 🟢 Sadece görünen video aktif
            );
          },
        ),
      );
    }
  }
}

class ReelsFilterText extends StatelessWidget {
  final String text;
  final bool isSelected;
  final VoidCallback onTap;

  // DÜZELTME: Kurucu ismi sınıf ismiyle aynı olmalı (_ReelsFilterText -> ReelsFilterText)
  const ReelsFilterText({
    super.key,
    required this.text,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        text,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.white60,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 16,
          shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
        ),
      ),
    );
  }
}

/// TEKİL REELS ÖĞESİ
// DÜZELTME: Sınıf ismi _ReelsItem yerine ReelsItem olmalı (Public erişim için)
class ReelsItem extends ConsumerStatefulWidget {
  final Post post;
  final bool isActive;

  const ReelsItem({super.key, required this.post, required this.isActive});

  @override
  ConsumerState<ReelsItem> createState() => _ReelsItemState();
}

class _ReelsItemState extends ConsumerState<ReelsItem> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // 🟢 State'i koru (Hafif kaydırmalarda yeniden yüklemeyi önler)

  VideoPlayerController? _videoController;
  late AnimationController _likeAnimController;
  late Animation<double> _likeAnimation;
  bool _isInitialized = false;
  bool _hasError = false; // 🟢 Hata durumu eklendi
  bool _isPlaying = true;
  bool _isMuted = true; // 🟢 Varsayılan olarak sessiz
  bool _isLongPressing = false; // 🟢 Basılı tutma durumu
  bool _wasPlayingBeforeLongPress = false; // 🟢 Basılı tutmadan önceki oynatma durumu
  double _likeRotation = 0.0; // 🟢 Animasyon açısı
  
  // 🟢 Local State for Optimistic Updates
  late bool _isLiked;
  late int _likesCount;
  late int _commentsCount;
  late int _repostsCount;
  late int _sharesCount;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
    _initPostData();
    
    _likeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _likeAnimation = Tween<double>(begin: 0.0, end: 1.2).animate(
      CurvedAnimation(parent: _likeAnimController, curve: Curves.elasticOut),
    );
    
    _likeAnimController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) _likeAnimController.reverse();
        });
      }
    });
  }

  void _initPostData() {
    final currentUser = ref.read(currentUserProvider).value;
    _isLiked = currentUser != null && widget.post.likes.contains(currentUser.$id);
    _likesCount = widget.post.likesCount;
    _commentsCount = widget.post.commentsCount;
    _repostsCount = widget.post.repostsCount;
    _sharesCount = widget.post.sharesCount;
  }

  @override
  void didUpdateWidget(ReelsItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.post != oldWidget.post) {
      _initPostData();
    }
    if (widget.isActive != oldWidget.isActive) {
      final controller = _videoController;
      if (controller != null && controller.value.isInitialized && !_hasError) {
        if (widget.isActive) {
          if (kIsWeb) controller.setVolume(0);
          controller.play();
        } else {
          controller.pause();
        }
      }
    }
  }

  Future<void> _initializeVideo() async {
    final mediaIds = widget.post.mediaIds;
    final fileId = mediaIds.isNotEmpty ? mediaIds.first : widget.post.imageId;
    
    if (fileId == null) {
      if (mounted) setState(() => _hasError = true);
      return;
    }

    final url = MediaService.getFileUrl(fileId);
    
    VideoPlayerController controller;

    try {
      // 🟢 CACHE KONTROLÜ (Performans Artışı)
      if (!kIsWeb) {
        final fileInfo = await DefaultCacheManager().getFileFromCache(url);
        if (!mounted) return;
        
        if (fileInfo != null && await fileInfo.file.exists()) {
          controller = VideoPlayerController.file(fileInfo.file); // Cache'den oynat
        } else {
          controller = VideoPlayerController.networkUrl(Uri.parse(url)); // Ağdan oynat
          DefaultCacheManager().getSingleFile(url).catchError((_) => File('')); // Arka planda indir
        }
      } else {
        controller = VideoPlayerController.networkUrl(Uri.parse(url));
      }

      _videoController = controller;

      // 🟢 Varsayılan olarak sessiz başlat
      await controller.setVolume(0);
      _isMuted = true;

      await controller.initialize();
      await controller.setLooping(true);
      
      // 📊 ANALYTICS: Video bittiğinde (Looping true olduğu için bu event tetiklenmeyebilir, 
      // ama completion rate için listener eklenebilir)
      controller.addListener(() {
        if (controller.value.position >= controller.value.duration) {
           // Video tamamlandı (Completion)
           // Bu event loop modunda her döngüde tetiklenir.
           // Algoritma için çok değerli bir veri (+40 puan).
           // Buradan parent widget'a callback ile bildirilebilir.
        }
      });
      
      // 🛠️ HATA ÇÖZÜMÜ: Aspect Ratio 0 ise hata fırlat (Widget çökmesini önler)
      if (controller.value.aspectRatio == 0) {
        throw Exception('Invalid aspect ratio: 0');
      }

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _hasError = false;
        });

        if (widget.isActive) {
          await controller.play();
        }
      }
    } catch (e) {
      debugPrint("Video initialization error: $e");
      if (mounted) {
        setState(() {
          _isInitialized = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _likeAnimController.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;

    // 🟢 Tıklama Mantığı: Sessizse sesi aç, sesliyse durdur/başlat
    if (_isMuted) {
      controller.setVolume(1.0);
      setState(() => _isMuted = false);
    } else {
      if (controller.value.isPlaying) {
        controller.pause();
        setState(() => _isPlaying = false);
      } else {
        // Sesi tekrar kapatmıyoruz, kaldığı yerden sesli devam etsin
        controller.play();
        setState(() => _isPlaying = true);
      }
    }
  }

  void _showMoreOptions(BuildContext context) {
    final currentUser = ref.read(currentUserProvider).value;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (currentUser != null && widget.post.userId == currentUser.$id)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Gönderiyi Sil', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deletePost(context);
                },
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.report_gmailerrorred_outlined, color: Colors.red),
                title: const Text('Şikayet Et', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Gönderi şikayet edildi. İncelemeye alındı.')),
                  );
                },
              ),
              if (currentUser != null)
                ListTile(
                  leading: const Icon(Icons.block_outlined),
                  title: const Text('Kullanıcıyı Engelle'),
                  onTap: () {
                    Navigator.pop(context);
                    _blockUser(context, currentUser);
                  },
                ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _deletePost(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Silinsin mi?'),
        content: const Text('Bu gönderiyi silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(postServiceProvider).deletePost(widget.post.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gönderi silindi')));
        ref.refresh(reelsPostsProvider); // Silme işleminde listeyi yenilemek mantıklı
        ref.refresh(feedPostsProvider);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Future<void> _blockUser(BuildContext context, models.User currentUser) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Engellensin mi?'),
        content: const Text('Bu kullanıcıyı engellemek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Engelle', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(blockServiceProvider).blockUser(
        currentUserId: currentUser.$id,
        targetUserId: widget.post.userId
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kullanıcı engellendi')));
        ref.refresh(reelsPostsProvider); // Engellemede listeyi yenile
        ref.refresh(feedPostsProvider);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 🟢 KeepAlive için gerekli

    final userAsync = ref.watch(userProvider(widget.post.userId));
    final currentUser = ref.watch(currentUserProvider).value;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. VİDEO KATMANI
        GestureDetector(
          onTap: _togglePlay,
          // 🟢 LONG PRESS (Basılı Tutunca Duraklat)
          onLongPressStart: (_) {
            final controller = _videoController;
            if (controller != null && controller.value.isInitialized) {
              if (controller.value.isPlaying) {
                _wasPlayingBeforeLongPress = true;
                controller.pause();
                setState(() {
                  _isPlaying = false;
                  _isLongPressing = true; // İkonları gizle
                });
              } else {
                _wasPlayingBeforeLongPress = false;
                setState(() => _isLongPressing = true); // Zaten duruyorsa sadece ikonları gizle
              }
            }
          },
          onLongPressEnd: (_) {
            final controller = _videoController;
            if (controller != null && controller.value.isInitialized && _wasPlayingBeforeLongPress) {
              controller.play();
              setState(() => _isPlaying = true);
            }
            setState(() => _isLongPressing = false); // İkonları geri getir
          },
          onDoubleTap: () async {
            setState(() {
              _likeRotation = (Random().nextDouble() - 0.5) * 0.5; // -15 ile +15 derece arası rastgele eğim
            });
            _likeAnimController.forward(from: 0.0);
            if (!_isLiked && currentUser != null) {
              // Optimistic Update (Anlık Tepki)
              setState(() {
                _isLiked = true;
                _likesCount++;
              });

              // ⚡ Global State Optimistic Update (Provider'ı anında güncelle)
              ref.read(reelsPostsProvider.notifier).toggleLikeOptimistically(widget.post.id, currentUser.$id);
              ref.read(feedPostsProvider.notifier).toggleLikeOptimistically(widget.post.id, currentUser.$id);

              try {
                await ref.read(postServiceProvider).toggleLike(
                  widget.post.id,
                  currentUser.$id,
                );
              } catch (e) {
                // Hata olursa geri al
                setState(() {
                  _isLiked = false;
                  _likesCount--;
                });
                ref.read(reelsPostsProvider.notifier).toggleLikeOptimistically(widget.post.id, currentUser.$id);
                ref.read(feedPostsProvider.notifier).toggleLikeOptimistically(widget.post.id, currentUser.$id);
              }
            }
          },
          child: Container(
            color: Colors.black,
            child: _hasError
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.white, size: 48),
                        const SizedBox(height: 8),
                        const Text('Video yüklenemedi', style: TextStyle(color: Colors.white)),
                        TextButton(
                          onPressed: () {
                            setState(() => _hasError = false);
                            _initializeVideo();
                          },
                          child: const Text('Tekrar Dene', style: TextStyle(color: AppColors.primaryGreen)),
                        )
                      ],
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      // 1. Video Player (Hazırsa göster)
                      // 🛠️ HATA ÇÖZÜMÜ: AspectRatio 0 kontrolü
                      if (_isInitialized && _videoController != null && _videoController!.value.aspectRatio > 0 && !_hasError)
                        Center(
                          child: AspectRatio(
                            aspectRatio: _videoController!.value.aspectRatio,
                            child: VideoPlayer(_videoController!),
                          ),
                        ),

                      // 2. Thumbnail (Video hazır değilse VEYA oynatılmıyorsa kapak olarak göster)
                      // 🛠️ EncodingError ÇÖZÜMÜ: imageId ile mediaIds.first aynıysa (yani thumbnail yoksa, video ID'si varsa)
                      // CachedNetworkImage'in videoyu indirmesini engelle.
                      // 🟢 EK KORUMA: mediaIds boşsa (eski veri) imageId muhtemelen videodur, gösterme.
                      if ((!_isInitialized || !_isPlaying || _hasError) && 
                          widget.post.imageId != null &&
                          widget.post.imageId!.isNotEmpty &&
                          widget.post.mediaIds.isNotEmpty && // Media listesi dolu olmalı (yeni sistem)
                          !widget.post.mediaIds.contains(widget.post.imageId) // imageId, medya listesinde YOKSA (yani ayrı bir thumbnail ise)
                         ) 
                        CachedNetworkImage(
                          imageUrl: MediaService.getFileUrl(widget.post.imageId!),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          // Video arkada oynuyorsa placeholder'ı kaldır, değilse göster
                          placeholder: (context, url) => Container(color: Colors.black),
                          errorWidget: (context, url, error) => Container(color: Colors.black),
                        ),

                      // 3. Loading Indicator (Her zaman üstte, yüklenirken)
                      if (!_isInitialized)
                        const Center(child: CircularProgressIndicator(color: Colors.white)),
                    ],
                  ),
          ),
        ),

        // 2. DURUM İKONLARI (Play / Mute)
        // 🟢 Basılı tutarken Play ikonunu gösterme (Video net görünsün)
        if (!_isPlaying && !_isMuted && !_isLongPressing)
          const Center(
            child: Icon(Icons.play_arrow, color: Colors.white54, size: 64),
          ),
        
        // 🟢 Sessiz İkonu (Video oynuyor ama sessizse göster)
        if (_isMuted && _isPlaying)
          const Center(
            child: Icon(Icons.volume_off, color: Colors.white54, size: 64),
          ),

        // ❤️ BEĞENİ ANİMASYONU (Overlay)
        Center(
          child: ScaleTransition(
            scale: _likeAnimation,
            child: Transform.rotate(
              angle: _likeRotation,
              child: const Icon(
                Icons.favorite, 
                color: Colors.white, 
                size: 120, // 🟢 Daha büyük
                shadows: [
                  Shadow(color: Colors.black54, blurRadius: 25, offset: Offset(0, 4)), // 🟢 Gölge efekti
                ],
              ),
            ),
          ),
        ),

        // 3. KARARTMA GRADIENT (Alt kısımdaki yazıların okunması için)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 200,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
          ),
        ),

        // 4. SOL ALT BİLGİLER (Kullanıcı, Açıklama)
        Positioned(
          bottom: 20,
          left: 16,
          right: 80, // Sağdaki butonlar için boşluk
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Kullanıcı Bilgisi
              userAsync.when(
                data: (userDoc) {
                  final data = userDoc.data;
                  final name = data['displayName'] ?? 'Kullanıcı';
                  final photoId = data['photoId'] ?? data['profileImageUrl'];
                  
                  return GestureDetector(
                    onTap: () => context.push('/profile/${widget.post.userId}'),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundImage: photoId != null 
                              ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId))
                              : null,
                          child: photoId == null ? const Icon(Icons.person, size: 16) : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Takip Et Butonu (Opsiyonel)
                        ReelsFollowButton(
                          targetUserId: widget.post.userId,
                          currentUserId: currentUser?.$id,
                        ),
                      ],
                    ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 12),
              // Açıklama
              Text(
                widget.post.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 8),
              // 🎵 Kayan Yazı (Müzik/Açıklama)
              Row(
                children: [
                  const Icon(Icons.music_note, color: Colors.white, size: 14),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: MediaQuery.of(context).size.width * 0.5,
                    height: 20,
                    child: MarqueeWidget(
                      child: Text(
                        'Orijinal Ses - ${userAsync.value?.data['displayName'] ?? 'Kullanıcı'}       ',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 5. SAĞ TARAFTAKİ AKSİYON BUTONLARI
        Positioned(
          bottom: 40,
          right: 10,
          child: Column(
            children: [
              // Beğeni
              // DÜZELTME: _ReelsActionButton -> ReelsActionButton
              ReelsActionButton(
                icon: _isLiked ? Icons.favorite : Icons.favorite_border,
                color: _isLiked ? Colors.red : Colors.white,
                label: '$_likesCount',
                isLike: true,
                onTap: () async {
                  if (currentUser == null) return;
                  
                  // Optimistic Update (Anlık Tepki)
                  setState(() {
                    if (_isLiked) {
                      _isLiked = false;
                      _likesCount--;
                    } else {
                      _isLiked = true;
                      _likesCount++;
                    }
                  });

                  // ⚡ Global State Optimistic Update
                  ref.read(reelsPostsProvider.notifier).toggleLikeOptimistically(widget.post.id, currentUser.$id);
                  ref.read(feedPostsProvider.notifier).toggleLikeOptimistically(widget.post.id, currentUser.$id);

                  try {
                    await ref.read(postServiceProvider).toggleLike(
                      widget.post.id,
                      currentUser.$id,
                    );
                  } catch (e) {
                    // Hata olursa geri al
                    setState(() {
                      if (_isLiked) {
                        _isLiked = false;
                        _likesCount--;
                      } else {
                        _isLiked = true;
                        _likesCount++;
                      }
                    });
                    ref.read(reelsPostsProvider.notifier).toggleLikeOptimistically(widget.post.id, currentUser.$id);
                    ref.read(feedPostsProvider.notifier).toggleLikeOptimistically(widget.post.id, currentUser.$id);
                  }
                },
              ),
              const SizedBox(height: 20),
              // Yorum
              ReelsActionButton(
                icon: Icons.chat_bubble_outline_rounded, // 🟢 Ana post ikonu
                label: '$_commentsCount',
                onTap: () async {
                  // 🆕 YENİ REELS YORUM AKIŞI
                  await showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent, // Arkadaki videoyu görmek için
                    builder: (context) => Container(
                      height: MediaQuery.of(context).size.height * 0.75, // Ekranın %75'ini kapla
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Column(
                        children: [
                          // Tutamaç (Handle)
                          Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 12),
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          // 📝 Kullanıcı Açıklaması (Caption)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.1))),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Kullanıcı adını userAsync'den alıyoruz (yukarıda tanımlı)
                                if (userAsync.hasValue)
                                  Text(
                                    userAsync.value!.data['displayName'] ?? 'Kullanıcı',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.post.content,
                                  style: const TextStyle(fontSize: 14),
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          // 💬 Yorumlar Listesi
                          Expanded(
                            child: CommentsSheet(
                              postId: widget.post.id, 
                              postOwnerId: widget.post.userId
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                  // Yorum yapıldıktan sonra sayaçları güncelle
                  // Yorum sayısını almak için postu yenile
                  final updatedPost = await ref.read(postServiceProvider).getPost(widget.post.id);
                  if (context.mounted) {
                    ref.read(reelsPostsProvider.notifier).updateSpecificPost(updatedPost);
                    ref.read(feedPostsProvider.notifier).updateSpecificPost(updatedPost);
                  }
                },
              ),
              const SizedBox(height: 20),
              // Repost (Sıralama değiştirildi, ana post ile aynı yapıldı)
              // DÜZELTME: _ReelsActionButton -> ReelsActionButton
              ReelsActionButton(
                icon: Icons.repeat_rounded, // 🟢 Ana post ikonu
                label: '$_repostsCount', // Repost sayısı
                onTap: () async {
                   // Repost mantığı (PostCard'daki gibi)
                   if (currentUser == null) return;
                   try {
                      final userProfile = await ref.read(currentUserProfileProvider.future);
                      final universityId = userProfile?['university'] as String?;
                      if (universityId == null) return;

                      // ⚡ Optimistic Update UI
                      setState(() => _repostsCount++);
                      ref.read(reelsPostsProvider.notifier).incrementRepostOptimistically(widget.post.id);
                      ref.read(feedPostsProvider.notifier).incrementRepostOptimistically(widget.post.id);

                      await ref.read(postServiceProvider).repost(widget.post, currentUser.$id, universityId);
                      
                      if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Repost yapıldı!')));
                      }
                   } catch (e) {
                     // Ağ hatası oluştu, orijinaline geri döndürmeyi garantilemek için fetch et
                     setState(() => _repostsCount--);
                     final updatedPost = await ref.read(postServiceProvider).getPost(widget.post.id);
                     if (context.mounted) {
                       ref.read(reelsPostsProvider.notifier).updateSpecificPost(updatedPost);
                       ref.read(feedPostsProvider.notifier).updateSpecificPost(updatedPost);
                     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
                     }
                   }
                }, 
              ),
              const SizedBox(height: 20),
              // Paylaş (Share)
              // DÜZELTME: _ReelsActionButton -> ReelsActionButton
              ReelsActionButton(
                icon: Icons.ios_share,
               label: '$_sharesCount', // Paylaşım sayısı
                onTap: () {
                   showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (context) => SharePostSheet(
                      postId: widget.post.id,
                      postContent: widget.post.content,
                    ),
                  );
                }, 
              ),
              const SizedBox(height: 20),
              // Daha Fazla (More)
              ReelsActionButton(
                icon: Icons.more_horiz,
                label: 'Diğer',
                onTap: () => _showMoreOptions(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// ➕ Reels İçin Akıllı Takip Butonu
class ReelsFollowButton extends ConsumerStatefulWidget {
  final String targetUserId;
  final String? currentUserId;

  const ReelsFollowButton({
    super.key,
    required this.targetUserId,
    required this.currentUserId,
  });

  @override
  ConsumerState<ReelsFollowButton> createState() => _ReelsFollowButtonState();
}

class _ReelsFollowButtonState extends ConsumerState<ReelsFollowButton> {
  bool _isFollowing = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkFollowStatus();
  }

  Future<void> _checkFollowStatus() async {
    if (widget.currentUserId == null || widget.currentUserId == widget.targetUserId) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final followService = ref.read(followServiceProvider);
    final followDoc = await followService.getFollowStatus(widget.currentUserId!, widget.targetUserId);

    if (mounted) {
      setState(() {
        _isFollowing = followDoc != null; // Status 'pending' olsa bile takip isteği gönderilmiş demektir
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    if (widget.currentUserId == null) return;

    // Optimistic Update (Anlık değişim)
    setState(() => _isFollowing = !_isFollowing);

    try {
      final followService = ref.read(followServiceProvider);
      if (_isFollowing) {
        await followService.followUser(
          currentUserId: widget.currentUserId!,
          targetUserId: widget.targetUserId,
        );
      } else {
        // Takipten çıkmak için followDocId lazım ama burada basitlik adına
        // servise "forceUnfollow" benzeri bir metod eklemek veya ID'yi tutmak gerekir.
        // Şimdilik UI'da değişiyor, tam unfollow için FollowService'de ID'siz unfollow desteği gerekebilir
        // veya getFollowStatus ile ID alıp silinebilir.
        final doc = await followService.getFollowStatus(widget.currentUserId!, widget.targetUserId);
        if (doc != null) {
          await followService.unfollowUser(followDocId: doc.$id);
        }
      }
    } catch (e) {
      // Hata olursa geri al
      if (mounted) setState(() => _isFollowing = !_isFollowing);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentUserId == widget.targetUserId) {
      return const SizedBox.shrink(); // Kendisi ise buton gösterme (veya "Ben" yazabilirsin)
    }

    if (_isLoading) return const SizedBox.shrink();

    return GestureDetector(
      onTap: _toggleFollow,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white),
          borderRadius: BorderRadius.circular(6),
          color: _isFollowing ? Colors.white.withOpacity(0.2) : Colors.transparent,
        ),
        child: Text(
          _isFollowing ? 'Takip Ediliyor' : 'Takip Et',
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

/// 📜 Kayan Yazı Widget'ı (Marquee)
class MarqueeWidget extends StatefulWidget {
  final Widget child;
  final Axis direction;
  final Duration animationDuration;
  final Duration pauseDuration;

  const MarqueeWidget({
    super.key,
    required this.child,
    this.direction = Axis.horizontal,
    this.animationDuration = const Duration(seconds: 6),
    this.pauseDuration = const Duration(seconds: 1),
  });

  @override
  State<MarqueeWidget> createState() => _MarqueeWidgetState();
}

class _MarqueeWidgetState extends State<MarqueeWidget> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scroll());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scroll() async {
    if (!mounted) return;
    while (_scrollController.hasClients) {
      await Future.delayed(widget.pauseDuration);
      if (_scrollController.hasClients && _scrollController.position.maxScrollExtent > 0) {
        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: widget.animationDuration,
          curve: Curves.linear,
        );
        await Future.delayed(widget.pauseDuration);
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0.0);
        }
      } else {
        await Future.delayed(widget.pauseDuration);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: widget.direction,
      controller: _scrollController,
      physics: const NeverScrollableScrollPhysics(),
      child: widget.child,
    );
  }
}

class ReelsActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool isLike;

  // DÜZELTME: Kurucu ismi sınıf ismiyle aynı olmalı (_ReelsActionButton -> ReelsActionButton)
  const ReelsActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
    this.isLike = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          if (isLike)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
              child: Icon(icon, key: ValueKey(icon), color: color, size: 30),
            )
          else
            Icon(icon, color: color, size: 30),
          const SizedBox(height: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
            child: Text(
              label,
              key: ValueKey(label),
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
