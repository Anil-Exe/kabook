import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appwrite/appwrite.dart';
import '../../../models/post_model.dart';
import '../../auth/data/auth_providers.dart';
import '../../follow/data/follow_service.dart';
import '../../post/data/providers/post_providers.dart';
import '../../block/data/block_service.dart';
import '../../../services/appwrite_service.dart';
import '../../../core/config/appwrite_config.dart';

/// 🔝 Yukarı Kaydırma Tetikleyicisi (KaBOOK yazısına basılınca çalışır)
final homeScrollToTopProvider = StateProvider<DateTime?>((ref) => null);

/// Filtre Durumu Modeli
class FeedFilterState {
  final bool isMyUniversity; // true: Üniversiteniz, false: Tüm Üniversiteler
  final bool isFollowingOnly; // true: Takip Edilenler, false: Herkes

  const FeedFilterState({
    this.isMyUniversity = true,
    this.isFollowingOnly = false,
  });

  FeedFilterState copyWith({
    bool? isMyUniversity,
    bool? isFollowingOnly,
  }) {
    return FeedFilterState(
      isMyUniversity: isMyUniversity ?? this.isMyUniversity,
      isFollowingOnly: isFollowingOnly ?? this.isFollowingOnly,
    );
  }
}

/// 🎛️ Filtre State Provider
final feedFilterProvider = StateProvider<FeedFilterState>((ref) {
  return const FeedFilterState();
});

/// 🔴 Reels Filtre Ayarları (Tüm/Üniversite/Takip)
final reelsFilterSettingsProvider = StateProvider<FeedFilterState>((ref) {
  return const FeedFilterState(
    isMyUniversity: true,
    isFollowingOnly: false,
  );
});

/// ♾️ REELS FEED NOTIFIER (Infinite Scroll & Algorithm)
final reelsPostsProvider = AsyncNotifierProvider.autoDispose<ReelsFeedNotifier, List<Post>>(ReelsFeedNotifier.new);

class ReelsFeedNotifier extends AutoDisposeAsyncNotifier<List<Post>> {
  String? _lastId;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  Timer? _snapshotTimer;

  @override
  Future<List<Post>> build() async {
    // 📌 SNAPSHOT MANTIĞI (20 Dakika Cache)
    // Provider dispose edilmesini engelle (keepAlive)
    final link = ref.keepAlive();
    
    // 20 dakika sonra link'i kapat -> Provider dispose olur -> Yeni veri çekilir
    _snapshotTimer?.cancel();
    _snapshotTimer = Timer(const Duration(minutes: 20), () {
      link.close();
    });

    // Filtre değiştiğinde listeyi sıfırla ve yeniden çek
    final filter = ref.watch(reelsFilterSettingsProvider);
    return _fetchPosts(filter: filter, isRefresh: true);
  }

  Future<List<Post>> _fetchPosts({required FeedFilterState filter, bool isRefresh = false}) async {
    if (isRefresh) {
      _lastId = null;
      _hasMore = true;
    }

    if (!_hasMore && !isRefresh) return [];

    final user = await ref.read(currentUserProvider.future);
    if (user == null) return [];

    final postService = ref.read(postServiceProvider);
    
    // 🎓 Üniversite Bilgisini Çek (Hem 'Eşit' hem 'Eşit Değil' sorgusu için gerekli)
    String? universityId;
    final userProfile = await ref.read(userProfileProvider(user.$id).future);
    universityId = userProfile?['university'];
    
    // Eğer kullanıcının üniversitesi yoksa filtreleme yapamayız, boş dön.
    if ((universityId == null || universityId.isEmpty)) return [];

    // Takip edilenleri HER ZAMAN çek (Gizlilik kontrolü için de gerekli)
    final followService = ref.read(followServiceProvider);
    final followingIds = await followService.getFollowingIds(user.$id);
    
    // Eğer "Takip Ettiklerim" seçiliyse ve kimseyi takip etmiyorsa boş dön
    if (filter.isFollowingOnly && followingIds.isEmpty) return [];

    // 🚫 ENGEL LİSTESİNİ ÇEK
    final blockService = ref.read(blockServiceProvider);
    final blockedIds = await blockService.getBlockedUserIds(user.$id);

    List<Post> allFilteredPosts = [];
    int attempts = 0;

    // 🔄 DÖNGÜ: Yeterli sayıda (örn. 5) filtrelenmiş video bulana kadar çekmeye devam et
    while (allFilteredPosts.length < 5 && _hasMore && attempts < 5) {
      attempts++;

      final newPosts = await postService.getFeed(
        limit: 20, // 🟢 Limit artırıldı
        cursor: _lastId,
        sortType: 'trending',
        mediaType: 'video',
        universityId: universityId,
        useUniversityFilter: filter.isMyUniversity,
        isFollowingOnly: filter.isFollowingOnly,
        followingIds: filter.isFollowingOnly ? followingIds : null, // Sadece takip filtresi açıksa ID gönder
      );

      if (newPosts.isEmpty) {
        _hasMore = false;
        break;
      }

      _lastId = newPosts.last.id;
      if (newPosts.length < 20) {
        _hasMore = false;
      }

      // 🛡️ GİZLİLİK VE ENGEL FİLTRESİ
      final usersToCheck = newPosts
          .map((p) => p.userId)
          .toSet()
          .where((id) => id != user.$id && !followingIds.contains(id) && !blockedIds.contains(id))
          .toList();

      Set<String> privateUserIds = {};

      if (usersToCheck.isNotEmpty) {
        try {
          final db = AppwriteService.databases;
          final result = await db.listDocuments(
            databaseId: AppwriteConfig.databaseId,
            collectionId: AppwriteConfig.usersCollectionId,
            queries: [
              Query.equal('userId', usersToCheck),
              Query.limit(100),
            ],
          );
          
          privateUserIds = result.documents
              .where((d) => d.data['isPrivate'] == true)
              .map((d) => d.data['userId'] as String)
              .toSet();
        } catch (e) {
          print('Reels privacy check error: $e');
        }
      }

      final filteredBatch = newPosts.where((post) {
        final uid = post.userId;
        
        // 1. Engellenenleri Gizle
        if (blockedIds.contains(uid)) return false;

        // 2. Filtre Kuralları
        if (filter.isFollowingOnly) {
          // A) Takip Ettiklerim Sekmesi
          if (uid == user.$id) return false; // Kendim hariç
          if (!followingIds.contains(uid)) return false; // Sadece takip ettiklerim
        } else if (!filter.isMyUniversity) {
          // B) Diğer Üniversiteler Sekmesi
          if (uid == user.$id) return false; // Kendim hariç
          if (post.university == universityId) return false; // Kendi üniversitem hariç
        } else {
          // C) Üniversiteniz Sekmesi (Sadece kendi üniversitem)
          if (post.university != null && post.university!.isNotEmpty && post.university != universityId) return false;
        }

        // 3. Gizlilik Kontrolü (Gizliyse ve takip etmiyorsam, kendim değilsem gizle)
        if (uid != user.$id && privateUserIds.contains(uid) && !followingIds.contains(uid)) return false;
        
        return true;
      }).toList();

      allFilteredPosts.addAll(filteredBatch);
    }

    // 🧠 Cursor hatasını önlemek için çeşitlendirmeyi EN SON yapıyoruz
    return postService.diversifyFeed(allFilteredPosts);
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    
    try {
      final filter = ref.read(reelsFilterSettingsProvider);
      final newPosts = await _fetchPosts(filter: filter);
      
      if (newPosts.isNotEmpty) {
        state = AsyncData([...state.value ?? [], ...newPosts]);
      }
    } catch (e) {
      print("Reels load more error: $e");
    } finally {
      _isLoadingMore = false;
    }
  }

  /// Listeyi baştan yükle (Pull-to-refresh için)
  Future<void> refresh() async {
    // state = const AsyncLoading(); // Mevcut listeyi korumak için loading durumuna çekmiyoruz
    final filter = ref.read(reelsFilterSettingsProvider);
    state = await AsyncValue.guard(() => _fetchPosts(filter: filter, isRefresh: true));
  }

  /// 🔄 Tek bir postu listede güncelle (Beğeni/Yorum sonrası senkronizasyon için)
  void updateSpecificPost(Post updatedPost) {
    state.whenData((posts) {
      final index = posts.indexWhere((p) => p.id == updatedPost.id);
      if (index != -1) {
        final newPosts = List<Post>.from(posts);
        newPosts[index] = updatedPost;
        // State'i güncelle ama loading'e sokma
        state = AsyncData(newPosts);
      }
    });
  }

  /// ⚡ OPTIMISTIC UPDATE: Beğeni (Ağ isteği beklemeden state'i günceller)
  void toggleLikeOptimistically(String postId, String userId) {
    state.whenData((posts) {
      final index = posts.indexWhere((p) => p.id == postId);
      if (index != -1) {
        final post = posts[index];
        try {
          // Not: Eğer Post modelinde copyWith metodu varsa 'post.copyWith(likes: ...)' kullanmak daha temizdir.
          final map = post.toMap();
          final likes = List<String>.from(map['likes'] ?? []);
          
          if (likes.contains(userId)) {
            likes.remove(userId);
          } else {
            likes.add(userId);
          }
          
          map['likes'] = likes;
          map['likesCount'] = likes.length;
          
          final newPosts = List<Post>.from(posts);
          newPosts[index] = Post.fromMap(map);
          state = AsyncData(newPosts);
        } catch (e) {
          print('Reels Optimistic Like Error: $e');
        }
      }
    });
  }

  /// ⚡ OPTIMISTIC UPDATE: Repost (Ağ isteği beklemeden state'i günceller)
  void incrementRepostOptimistically(String postId) {
    state.whenData((posts) {
      final index = posts.indexWhere((p) => p.id == postId);
      if (index != -1) {
        final post = posts[index];
        try {
          final map = post.toMap();
          map['repostsCount'] = (map['repostsCount'] ?? 0) + 1;
          final newPosts = List<Post>.from(posts);
          newPosts[index] = Post.fromMap(map);
          state = AsyncData(newPosts);
        } catch (e) {
          print('Reels Optimistic Repost Error: $e');
        }
      }
    });
  }
}

/// ♾️ HOME FEED NOTIFIER (Infinite Scroll & Algorithm)
final feedPostsProvider = AsyncNotifierProvider.autoDispose<HomeFeedNotifier, List<Post>>(HomeFeedNotifier.new);

class HomeFeedNotifier extends AutoDisposeAsyncNotifier<List<Post>> {
  String? _lastId;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  Timer? _snapshotTimer;

  @override
  Future<List<Post>> build() async {
    // 📌 SNAPSHOT MANTIĞI (20 Dakika Cache)
    final link = ref.keepAlive();
    
    _snapshotTimer?.cancel();
    _snapshotTimer = Timer(const Duration(minutes: 20), () {
      link.close();
    });

    final filter = ref.watch(feedFilterProvider);
    return _fetchPage(filter: filter, isRefresh: true);
  }

  Future<List<Post>> _fetchPage({required FeedFilterState filter, bool isRefresh = false}) async {
    if (isRefresh) {
      _lastId = null;
      _hasMore = true;
    }

    if (!_hasMore && !isRefresh) return [];

    final user = await ref.read(currentUserProvider.future);
    if (user == null) return [];

    final postService = ref.read(postServiceProvider);
    final followService = ref.read(followServiceProvider);
    final blockService = ref.read(blockServiceProvider);

    // 🎓 Üniversite Bilgisini Çek
    String? universityId;
    final userProfile = await ref.read(userProfileProvider(user.$id).future);
    universityId = userProfile?['university'];
    
    // Üniversite bilgisi yoksa akış gösterilemez (Filtre mantığı gereği)
    if ((universityId == null || universityId.isEmpty)) return [];

    // 1. Takip Edilenleri ve Engellenenleri Çek
    // Takip edilenleri HER ZAMAN çekiyoruz (Gizlilik kontrolü için gerekli)
    // Eğer "Herkes" sekmesindeysek bile, takip ettiğimiz gizli hesapları görebilmeliyiz.
    final followingIds = await followService.getFollowingIds(user.$id);
    final blockedIds = await blockService.getBlockedUserIds(user.$id);

    // Eğer "Sadece Takip Edilenler" seçiliyse ve kimseyi takip etmiyorsa boş dön
    if (filter.isFollowingOnly && followingIds.isEmpty) return [];

    List<Post> allFilteredPosts = [];
    int attempts = 0;

    // 🔄 DÖNGÜ: Yeterli sayıda (örn. 10) filtrelenmiş post bulana kadar çekmeye devam et
    // Client-side filtreleme (Gizlilik/Engel/Kendi Postum) nedeniyle bazen 15 postun hepsi elenebilir.
    // Bu durumda kullanıcıya boş sayfa göstermemek için recursive fetch yapıyoruz.
    while (allFilteredPosts.length < 10 && _hasMore && attempts < 5) {
      attempts++;

      final newPosts = await postService.getFeed(
        limit: 20, // 🟢 Limit artırıldı (Daha fazla şans)
        cursor: _lastId,
        sortType: 'trending',
        mediaType: null,
        universityId: universityId,
        useUniversityFilter: filter.isMyUniversity,
        isFollowingOnly: filter.isFollowingOnly,
        followingIds: filter.isFollowingOnly ? followingIds : null, // Doğru
      );

      if (newPosts.isEmpty) {
        _hasMore = false;
        break;
      }

      _lastId = newPosts.last.id;
      if (newPosts.length < 20) {
        _hasMore = false;
      }

      // 🛡️ GİZLİLİK VE ENGEL FİLTRESİ
      final usersToCheck = newPosts
          .map((p) => p.userId)
          .toSet()
          .where((id) => id != user.$id && !followingIds.contains(id) && !blockedIds.contains(id))
          .toList();

      Set<String> privateUserIds = {};

      if (usersToCheck.isNotEmpty) {
        try {
          final db = AppwriteService.databases;
          final result = await db.listDocuments(
            databaseId: AppwriteConfig.databaseId,
            collectionId: AppwriteConfig.usersCollectionId,
            queries: [
              Query.equal('userId', usersToCheck),
              Query.limit(100),
            ],
          );
          
          privateUserIds = result.documents
              .where((d) => d.data['isPrivate'] == true)
              .map((d) => d.data['userId'] as String)
              .toSet();
        } catch (e) {
          print('Home privacy check error: $e');
        }
      }

      final filteredBatch = newPosts.where((post) {
        final uid = post.userId;
        
        // 1. Engellenenleri Gizle
        if (blockedIds.contains(uid)) return false;

        // 2. Takip Filtresi Aktifse
        if (filter.isFollowingOnly && !followingIds.contains(uid)) return false;

        // 3. Kendi Postlarımın Görünürlüğü
        if (uid == user.$id) {
          // Takip edilenler veya Diğer Üniversiteler sekmesinde kendi postum görünmesin
          if (filter.isFollowingOnly) return false;
          if (!filter.isMyUniversity) return false;
          return true;
        }

        // 4. Diğer Üniversiteler Filtresi (Kendi üniversitemi çıkar)
        if (!filter.isMyUniversity && post.university == universityId) return false;

        // 5. Gizli Hesap Kontrolü
        if (uid != user.$id && privateUserIds.contains(uid) && !followingIds.contains(uid)) return false;

        return true;
      }).toList();

      allFilteredPosts.addAll(filteredBatch);
    }

    // 🧠 Cursor hatasını önlemek için çeşitlendirmeyi EN SON yapıyoruz
    return postService.diversifyFeed(allFilteredPosts);
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;

    try {
      final filter = ref.read(feedFilterProvider);
      final newPosts = await _fetchPage(filter: filter);
      if (newPosts.isNotEmpty) {
        state = AsyncData([...state.value ?? [], ...newPosts]);
      }
    } catch (e) {
      print("Home load more error: $e");
    } finally {
      _isLoadingMore = false;
    }
  }
  
  Future<void> refresh() async {
    // state = const AsyncLoading(); // Mevcut listeyi korumak için loading durumuna çekmiyoruz
    final filter = ref.read(feedFilterProvider);
    state = await AsyncValue.guard(() => _fetchPage(filter: filter, isRefresh: true));
  }

  /// 🔄 Tek bir postu listede güncelle (Beğeni/Yorum sonrası senkronizasyon için)
  void updateSpecificPost(Post updatedPost) {
    state.whenData((posts) {
      final index = posts.indexWhere((p) => p.id == updatedPost.id);
      if (index != -1) {
        final newPosts = List<Post>.from(posts);
        newPosts[index] = updatedPost;
        // State'i güncelle ama loading'e sokma
        state = AsyncData(newPosts);
      }
    });
  }

  /// ⚡ OPTIMISTIC UPDATE: Beğeni (Ağ isteği beklemeden state'i günceller)
  void toggleLikeOptimistically(String postId, String userId) {
    state.whenData((posts) {
      final index = posts.indexWhere((p) => p.id == postId);
      if (index != -1) {
        final post = posts[index];
        try {
          final map = post.toMap();
          final likes = List<String>.from(map['likes'] ?? []);
          
          if (likes.contains(userId)) {
            likes.remove(userId);
          } else {
            likes.add(userId);
          }
          
          map['likes'] = likes;
          map['likesCount'] = likes.length;
          
          final newPosts = List<Post>.from(posts);
          newPosts[index] = Post.fromMap(map);
          state = AsyncData(newPosts);
        } catch (e) {
          print('Home Optimistic Like Error: $e');
        }
      }
    });
  }

  /// ⚡ OPTIMISTIC UPDATE: Repost (Ağ isteği beklemeden state'i günceller)
  void incrementRepostOptimistically(String postId) {
    state.whenData((posts) {
      final index = posts.indexWhere((p) => p.id == postId);
      if (index != -1) {
        final post = posts[index];
        try {
          final map = post.toMap();
          map['repostsCount'] = (map['repostsCount'] ?? 0) + 1;
          final newPosts = List<Post>.from(posts);
          newPosts[index] = Post.fromMap(map);
          state = AsyncData(newPosts);
        } catch (e) {
          print('Home Optimistic Repost Error: $e');
        }
      }
    });
  }
}