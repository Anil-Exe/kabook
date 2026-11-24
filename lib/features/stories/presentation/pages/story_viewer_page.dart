import 'dart:async';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:appwrite/models.dart' as models;
import '../../../../services/appwrite_service.dart';
import '../../data/story_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../../utils/time_ago.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../messages/data/message_providers.dart'; // Mesaj servisi için

class StoryViewerPage extends ConsumerStatefulWidget {
  // Artık tek bir liste değil, tüm feed yapısını alıyoruz
  final List<Map<String, dynamic>> feedData;
  final int initialUserIndex;

  const StoryViewerPage({
    super.key, 
    required this.feedData, 
    required this.initialUserIndex
  });

  @override
  ConsumerState<StoryViewerPage> createState() => _StoryViewerPageState();
}

class _StoryViewerPageState extends ConsumerState<StoryViewerPage> {
  late int _currentUserIndex;
  late int _currentStoryIndex;
  late PageController _pageController;
  
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  Timer? _timer;
  double _progress = 0.0;
  Duration _storyDuration = const Duration(seconds: 5);
  bool _isPaused = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    _currentUserIndex = widget.initialUserIndex;
    _currentStoryIndex = 0;
    _pageController = PageController(initialPage: _currentUserIndex);
    
    _loadStoryAndStartTimer();
    _markStoryAsViewed();

    // Klavye açılınca timer'ı durdur
    _replyFocusNode.addListener(() {
      if (_replyFocusNode.hasFocus) {
        _pauseTimer();
      } else {
        _resumeTimer();
      }
    });
  }

  List<models.Document> get _currentStories => 
      widget.feedData[_currentUserIndex]['stories'] as List<models.Document>;

  models.Document get _currentStory => _currentStories[_currentStoryIndex];

  void _loadStoryAndStartTimer() {
    if (!mounted) return;

    final story = _currentStory;
    final isVideo = story.data['mediaType'] == 'video';
    final musicUrl = story.data['musicUrl'];

    _audioPlayer.stop(); // Önceki müziği durdur
    _videoController?.dispose();
    _videoController = null;

    if (isVideo) {
      final videoUrl = AppwriteService.getFileViewUrl(story.data['mediaUrl']);
      _videoController = VideoPlayerController.networkUrl(Uri.parse(videoUrl))
        ..initialize().then((_) {
          // Eğer müzik eklenmişse videonun kendi sesini 0'a çek (Mute)
          if (musicUrl != null && musicUrl.isNotEmpty) {
            _videoController!.setVolume(0.0);
          } else {
            _videoController!.setVolume(1.0);
          }
          
          _storyDuration = _videoController!.value.duration; // Süreyi videonun süresine ayarla
          if (mounted) setState(() => _progress = 0.0);
          
          if (!_isPaused) {
            _videoController!.play();
            _startTimer();
          }
        });
    } else {
      final durationInSeconds = story.data['duration'] as int? ?? 5;
      _storyDuration = Duration(seconds: durationInSeconds);
      setState(() => _progress = 0.0);
      _startTimer();
    }
    
    // Müzik varsa çalmaya başla
    if (musicUrl != null && musicUrl.isNotEmpty) {
      _audioPlayer.play(UrlSource(musicUrl));
      _audioPlayer.setReleaseMode(ReleaseMode.loop);
    }
  }

  void _markStoryAsViewed() {
    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) return;

    final storyId = _currentStory.$id;
    final ownerId = _currentStory.data['userId'];
    
    // Kendi hikayesi değilse servise bildir ve anlık UI state'ini güncelle
    if (currentUser.$id != ownerId) {
      ref.read(storyServiceProvider).viewStory(storyId, currentUser.$id, ownerId);
      
      // Anlık UI'da da görünmesi için local veriyi güncelle (Profil/Home tutarlılığı için)
      List<String> viewers = List<String>.from(_currentStory.data['viewers'] ?? []);
      if (!viewers.contains(currentUser.$id)) viewers.add(currentUser.$id);
      _currentStory.data['viewers'] = viewers;
    }
  }

  void _startTimer() {
    if (_isPaused) return;
    _timer?.cancel();
    const tick = Duration(milliseconds: 50);
    final totalTicks = _storyDuration.inMilliseconds / tick.inMilliseconds;
    if (totalTicks == 0) return;
    final progressIncrement = 1.0 / totalTicks;

    _timer = Timer.periodic(tick, (timer) {
      if (!mounted || _isPaused) {
        timer.cancel();
        return;
      }
      setState(() {
        _progress += progressIncrement;
        if (_progress >= 1.0) {
          _nextStory();
        }
      });
    });
  }

  void _pauseTimer() {
    _isPaused = true;
    _timer?.cancel();
    _audioPlayer.pause();
    _videoController?.pause();
  }

  void _resumeTimer() {
    _isPaused = false;
    _startTimer();
    if (_currentStory.data['musicUrl'] != null) {
      _audioPlayer.resume();
    }
    _videoController?.play();
  }

  void _nextStory() {
    _timer?.cancel();
    
    // Mevcut kullanıcının hikayeleri bitti mi?
    if (_currentStoryIndex < _currentStories.length - 1) {
      // Hayır, sıradaki hikayeye geç
      setState(() {
        _currentStoryIndex++;
      });
      _loadStoryAndStartTimer();
      _markStoryAsViewed();
    } else {
      // Evet, sıradaki kullanıcıya geç
      if (_currentUserIndex < widget.feedData.length - 1) {
        setState(() {
          _currentUserIndex++;
          _currentStoryIndex = 0;
        });
        // PageView'ı kaydır
        _pageController.animateToPage(
          _currentUserIndex,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
        _loadStoryAndStartTimer();
        _markStoryAsViewed();
      } else {
        // Herkesin hikayesi bitti, kapat
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  void _previousStory() {
    _timer?.cancel();
    
    if (_currentStoryIndex > 0) {
      // Önceki hikayeye dön
      setState(() {
        _currentStoryIndex--;
      });
      _loadStoryAndStartTimer();
    } else {
      // Önceki kullanıcıya dön
      if (_currentUserIndex > 0) {
        setState(() {
          _currentUserIndex--;
          // Önceki kullanıcının son hikayesine git
          _currentStoryIndex = (widget.feedData[_currentUserIndex]['stories'] as List).length - 1;
        });
        _pageController.animateToPage(
          _currentUserIndex,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
        _loadStoryAndStartTimer();
      } else {
        // İlk kullanıcının ilk hikayesindeyiz, baştan başlat
        setState(() {
          _currentStoryIndex = 0;
          _progress = 0.0;
        });
        _startTimer();
      }
    }
  }

  Future<void> _shareStory() async {
    final story = _currentStory;
    final url = AppwriteService.getFileViewUrl(story.data['mediaUrl']);
    final isVideo = story.data['mediaType'] == 'video';
    
    _pauseTimer(); // Paylaşırken durdur

    try {
      // Dosyayı indir
      final request = await HttpClient().getUrl(Uri.parse(url));
      final response = await request.close();
      final bytes = await response.expand((element) => element).toList();
      
      final tempDir = await getTemporaryDirectory();
      final ext = isVideo ? 'mp4' : 'jpg';
      final file = File('${tempDir.path}/story_share_${story.$id}.$ext');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles([XFile(file.path)], text: 'KaBOOK Story Paylaşımı');
    } catch (e) {
      debugPrint('Paylaşım hatası: $e');
    } finally {
      _resumeTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _replyController.dispose();
    _replyFocusNode.dispose();
    _pageController.dispose();
    _audioPlayer.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(), // Elle kaydırmayı kapatıyoruz, tıklama ile yöneteceğiz
        itemCount: widget.feedData.length,
        itemBuilder: (context, userIndex) {
          // Sadece aktif kullanıcıyı render et (Performans için)
          if (userIndex != _currentUserIndex) return const SizedBox.shrink();
          
          return _buildStoryView();
        },
      ),
    );
  }

  Widget _buildStoryView() {
    final story = _currentStory;
    final imageUrl = AppwriteService.getFileViewUrl(story.data['mediaUrl']);
    final currentUserId = ref.watch(currentUserProvider).value?.$id;
    final likedBy = List<String>.from(story.data['likedBy'] ?? []);

    return GestureDetector(
      onTapDown: (_) => _pauseTimer(),
      onTapUp: (details) => _handleTapUp(details),
      /* Eski gesture logic'i _handleTapUp içine taşıdım
      onTapUp: (details) {
        final width = MediaQuery.of(context).size.width;
        if (details.globalPosition.dx < width / 3) {
          _previousStory();
        } else {
          _nextStory();
        }
      },
      */
      child: Stack(
        children: [
          // Görsel
          Center(
            child: _videoController != null && _videoController!.value.isInitialized
              ? AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio,
                  child: VideoPlayer(_videoController!),
                )
              : CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => const Center(child: CircularProgressIndicator(color: Colors.white)),
                  errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.white),
                ),
          ),

          // Üst Kısım
          Padding(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10, left: 8, right: 8),
            child: _buildHeader(),
          ),

          // Caption
          if (story.data['caption'] != null)
            Positioned(
              bottom: 80,
              left: 20,
              right: 20,
              child: Text(
                story.data['caption'],
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white, 
                  fontSize: 18, 
                  backgroundColor: Colors.black45,
                  fontWeight: FontWeight.w500
                ),
              ),
            ),
          
          // Konum
          if (story.data['location'] != null)
             Positioned(
              top: 100,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.red, size: 14),
                    const SizedBox(width: 4),
                    Text(story.data['location'], style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
             ),

          // Görüntüleyenler Butonu
          _buildViewersButton(),

          // 💬 Hızlı Yanıt Kutusu (Alt Kısım)
          _buildReplyInput(),
        ],
      ),
    );
  }

  void _handleTapUp(TapUpDetails details) {
    if (_replyFocusNode.hasFocus) {
      // Klavye açıksa kapat ve devam et
      FocusScope.of(context).unfocus();
      _resumeTimer();
      return;
    }

    _resumeTimer();
    final width = MediaQuery.of(context).size.width;
    if (details.globalPosition.dx < width / 3) {
      _previousStory();
    } else {
      _nextStory();
    }
  }

  Widget _buildReplyInput() {
    final story = _currentStory;
    final isOwner = story.data['userId'] == ref.watch(currentUserProvider).value?.$id;
    
    // Kendi hikayemize cevap veremeyiz
    if (isOwner) return const SizedBox.shrink();

    final likedBy = List<String>.from(story.data['likedBy'] ?? []);
    final isLiked = likedBy.contains(ref.watch(currentUserProvider).value?.$id);

    return Positioned(
      bottom: MediaQuery.of(context).viewInsets.bottom + 20, // Klavye üstüne çık
      left: 16,
      right: 16,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _replyController,
              focusNode: _replyFocusNode,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Mesaj gönder...',
                hintStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.2),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: _sendReply,
                ),
              ),
            ),
          ),
          // 📤 Gönder Butonu (DM)
          IconButton(
            icon: const Icon(Icons.send_outlined, color: Colors.white, size: 28), // Kağıt uçak ikonu
            onPressed: () => _showSendStorySheet(context),
          ),
          const SizedBox(width: 10),
          // Beğeni butonu da eklenebilir buraya
          IconButton(
            icon: Icon(
              isLiked ? Icons.favorite : Icons.favorite_border, 
              color: isLiked ? Colors.red : Colors.white, 
              size: 30
            ),
            onPressed: () {
              final currentUser = ref.read(currentUserProvider).value;
              if (currentUser != null) {
                setState(() {
                  // Sadece lokal listeyi değiştir UI anında güncellensin
                  if (isLiked) {
                    likedBy.remove(currentUser.$id);
                  } else {
                    likedBy.add(currentUser.$id);
                  }
                  story.data['likedBy'] = likedBy;
                });
                // Servise listeyi değil, sadece ID'leri gönderiyoruz. Servis kendisi güncelleyecek.
                ref.read(storyServiceProvider).toggleLikeStory(story.$id, currentUser.$id);
              }
            },
          )
        ],
      ),
    );
  }

  // 📤 Hikayeyi Başkasına Gönderme Penceresi
  void _showSendStorySheet(BuildContext context) {
    _pauseTimer();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            // Mevcut sohbetleri getir (Hızlı gönderim için)
            final chatsAsync = ref.watch(myChatsProvider);
            
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("Şuna Gönder", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const Divider(color: Colors.grey),
                Expanded(
                  child: chatsAsync.when(
                    data: (chats) {
                      if (chats.isEmpty) return const Center(child: Text("Sohbet bulunamadı.", style: TextStyle(color: Colors.white)));
                      
                      return ListView.builder(
                        itemCount: chats.length,
                        itemBuilder: (context, index) {
                          final chat = chats[index];
                          final isGroup = chat.data['type'] == 'group';
                          final name = isGroup ? chat.data['groupName'] : "Sohbet"; // Basitlik için, detaylı isim MessagePage mantığıyla çekilebilir
                          
                          // Birebir sohbetse karşı tarafın ismini bulmak için basit bir Text gösteriyoruz
                          // (Daha detaylı UI için MessagePage'deki mantık buraya taşınabilir)
                          
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.grey[800],
                              child: Icon(isGroup ? Icons.groups : Icons.person, color: Colors.white),
                            ),
                            title: Text(isGroup ? name : "Kullanıcı", style: const TextStyle(color: Colors.white)), 
                            trailing: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, shape: const StadiumBorder()),
                              onPressed: () {
                                _sendStoryToChat(chat.$id);
                                Navigator.pop(context);
                              },
                              child: const Text("Gönder", style: TextStyle(color: Colors.white)),
                            ),
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (_,__) => const Center(child: Text("Hata oluştu", style: TextStyle(color: Colors.white))),
                  ),
                ),
              ],
            );
          }
        );
      },
    ).then((_) => _resumeTimer());
  }

  // Seçilen sohbete hikayeyi gönder
  Future<void> _sendStoryToChat(String chatId) async {
    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) return;

    try {
      await ref.read(messageServiceProvider).sendMessage(
        chatId: chatId,
        senderId: currentUser.$id,
        content: "Hikaye gönderdi",
        type: 'story_reply', // Karşı taraf tıklayınca hikayeyi açar
        fileId: _currentStory.data['mediaUrl'],
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hikaye gönderildi!')));
    } catch (e) {
      debugPrint("Gönderme hatası: $e");
    }
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;

    final currentUser = ref.read(currentUserProvider).value;
    final targetUserId = _currentStory.data['userId'];
    final storyImageId = _currentStory.data['mediaUrl'];
    
    if (currentUser == null) return;

    _replyController.clear();
    FocusScope.of(context).unfocus();
    _resumeTimer();

    try {
      // 1. Sohbeti bul veya oluştur
      final chatDoc = await ref.read(messageServiceProvider).getOrCreateDirectChat(
        currentUserId: currentUser.$id,
        targetUserId: targetUserId,
      );

      // 2. Mesajı gönder (Hikaye referansı ile)
      await ref.read(messageServiceProvider).sendMessage(
        chatId: chatDoc.$id,
        senderId: currentUser.$id,
        content: text, 
        type: 'story_reply', // ✅ GÜNCELLENDİ: Özel story reply tipi
        fileId: storyImageId, // Hikaye resmini ekle
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yanıt gönderildi'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      debugPrint("Mesaj gönderme hatası: $e");
    }
  }

  Widget _buildHeader() {
    final story = _currentStory;
    final userId = story.data['userId'];
    final createdAt = DateTime.parse(story.$createdAt);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Progress Barlar
        Row(
          children: List.generate(_currentStories.length, (index) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                child: LinearProgressIndicator(
                  value: index == _currentStoryIndex ? _progress : (index < _currentStoryIndex ? 1.0 : 0.0),
                  backgroundColor: Colors.white.withOpacity(0.3),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 2.5,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        // Kullanıcı Bilgisi
        Consumer(
          builder: (context, ref, _) {
            final userAsync = ref.watch(userProvider(userId));
            return userAsync.when(
              data: (user) {
                final photoId = user.data['photoId'];
                final imageUrl = photoId != null ? AppwriteService.getFileViewUrl(photoId) : null;
                final displayName = user.data['displayName'] ?? 'Kullanıcı';
                
                return Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundImage: imageUrl != null ? CachedNetworkImageProvider(imageUrl) : null,
                      child: imageUrl == null ? const Icon(Icons.person, size: 16) : null,
                    ),
                    const SizedBox(width: 8),
                    Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 2)])),
                    const SizedBox(width: 8),
                    Text(timeAgo(createdAt), style: const TextStyle(color: Colors.white70, fontSize: 12, shadows: [Shadow(blurRadius: 2)])),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.share, color: Colors.white),
                      onPressed: _shareStory,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                    )
                  ],
                );
              },
              loading: () => const SizedBox(height: 36),
              error: (_, __) => const SizedBox.shrink(),
            );
          }
        ),
      ],
    );
  }

  Widget _buildViewersButton() {
    final story = _currentStory;
    final isOwner = story.data['userId'] == ref.watch(currentUserProvider).value?.$id;
    final viewers = List<String>.from(story.data['viewers'] ?? []);
    final likedBy = List<String>.from(story.data['likedBy'] ?? []);

    if (!isOwner) return const SizedBox.shrink();

    return Positioned(
      bottom: 20,
      left: 0,
      right: 0,
      child: GestureDetector(
        onTap: () {
          _timer?.cancel(); // Sheet açılınca durdur
          _showViewersBottomSheet(context, viewers, likedBy).then((_) => _startTimer()); // Kapanınca devam et
        },
        child: Column(
          children: [
            const Icon(Icons.keyboard_arrow_up, color: Colors.white),
            Text("${viewers.length} görüntüleme", style: const TextStyle(color: Colors.white, shadows: [Shadow(blurRadius: 2)])),
          ],
        ),
      ),
    );
  }
}

Future<void> _showViewersBottomSheet(BuildContext context, List<String> viewerIds, List<String> likedBy) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.grey[900],
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) {
      return _ViewersSheet(viewerIds: viewerIds, likedBy: likedBy);
    },
  );
}

class _ViewersSheet extends StatelessWidget {
  final List<String> viewerIds;
  final List<String> likedBy;
  const _ViewersSheet({required this.viewerIds, required this.likedBy});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey,
              tabs: [
                Tab(text: "Görüntüleyenler"),
                Tab(text: "Beğenenler"),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // 1. Görüntüleyenler Sekmesi
                  viewerIds.isEmpty
                      ? const Center(child: Text("Henüz kimse görüntülemedi.", style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 8),
                          itemCount: viewerIds.length,
                          itemBuilder: (context, index) => _ViewerTile(
                            userId: viewerIds[index], 
                            isLiked: likedBy.contains(viewerIds[index])
                          ),
                        ),
                        
                  // 2. Beğenenler Sekmesi
                  likedBy.isEmpty
                      ? const Center(child: Text("Henüz beğeni yok.", style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 8),
                          itemCount: likedBy.length,
                          itemBuilder: (context, index) => _ViewerTile(
                            userId: likedBy[index], 
                            isLiked: true
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerTile extends ConsumerWidget {
  final String userId;
  final bool isLiked;
  const _ViewerTile({required this.userId, required this.isLiked});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProvider(userId));
    return userAsync.when(
      data: (user) {
        final photoId = user.data['photoId'];
        final imageUrl = photoId != null ? AppwriteService.getFileViewUrl(photoId) : null;
        return ListTile(
          leading: CircleAvatar(backgroundImage: imageUrl != null ? CachedNetworkImageProvider(imageUrl) : null, child: imageUrl == null ? const Icon(Icons.person) : null),
          title: Text(user.data['displayName'] ?? 'Kullanıcı', style: const TextStyle(color: Colors.white)),
          subtitle: Text('@${user.data['username'] ?? ''}', style: const TextStyle(color: Colors.grey)),
          trailing: isLiked ? const Icon(Icons.favorite, color: Colors.red) : null,
        );
      },
      loading: () => const ListTile(leading: CircleAvatar(), title: Text("Yükleniyor...", style: TextStyle(color: Colors.white))),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
