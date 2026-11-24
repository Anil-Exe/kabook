import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart'; // 🆕 Eklendi
import 'package:path_provider/path_provider.dart'; // 🆕 Eklendi

import '../../../../core/theme/app_theme.dart';
import '../../../../services/image_upload_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../follow/data/follow_service.dart';
import '../../data/providers/post_providers.dart';
import '../../../home/data/feed_provider.dart';
import '../../../../utils/custom_popup.dart';

class CreatePostPage extends ConsumerStatefulWidget {
  const CreatePostPage({super.key});

  @override
  ConsumerState<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends ConsumerState<CreatePostPage> {
  final _contentController = TextEditingController();
  List<XFile> _selectedMedia = []; // 🆕 Çoklu medya listesi
  String _mediaType = 'image'; // 'image' veya 'video'
  String? _thumbnailPath; // 🆕 Thumbnail dosya yolu
  bool _isLoading = false;

  // 0 = Genel, 1 = Yardım
  int _postType = 0;

  final List<String> _helpCategories = [
    'İş',
    'Konaklama',
    'Sosyal',
    'Ulaşım',
    'Ders'
  ];
  String _selectedHelpCategory = 'İş';

  // Etiketleme değişkenleri
  List<models.Document> _mentionSuggestions = [];
  bool _showMentions = false;
  String? _currentMentionQuery;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  // 📸 Kamera ile Fotoğraf Çek
  Future<void> _pickCamera() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera);
    if (picked != null) {
      setState(() {
        if (_mediaType == 'video') {
          _selectedMedia.clear();
        }
        _mediaType = 'image';
        _selectedMedia.add(picked);
      });
    }
  }

  // 🖼️ Galeriden Çoklu Fotoğraf Seç (Dump)
  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final pickedList = await picker.pickMultiImage();
    if (pickedList.isNotEmpty) {
      setState(() {
        if (_mediaType == 'video') {
          _selectedMedia.clear();
        }
        _mediaType = 'image';
        _selectedMedia.addAll(pickedList);
      });
    }
  }

  // 🎥 Video Seç (Reels)
  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked != null) {
      // 📏 Boyut Kontrolü (35 MB)
      final sizeInBytes = await picked.length();
      if (sizeInBytes > 35 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video boyutu 35 MB\'dan büyük olamaz.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // ⏱️ Süre Kontrolü (120 saniye)
      VideoPlayerController? controller;
      try {
        if (kIsWeb) {
          controller = VideoPlayerController.networkUrl(Uri.parse(picked.path));
        } else {
          controller = VideoPlayerController.file(File(picked.path));
        }
        
        await controller.initialize();
        if (controller.value.duration.inSeconds > 120) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Video süresi 120 saniyeden uzun olamaz.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          await controller.dispose();
          return;
        }
        await controller.dispose();
      } catch (e) {
        controller?.dispose();
        debugPrint('Video süre kontrolü hatası: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Video formatı desteklenmiyor veya dosya bozuk.')),
          );
        }
        return; // 🛑 Hata varsa işlemi durdur, seçimi iptal et.
      }

      // 🖼️ Thumbnail Oluştur (Sadece Mobil)
      if (!kIsWeb) {
        try {
          final fileName = await VideoThumbnail.thumbnailFile(
            video: picked.path,
            thumbnailPath: (await getTemporaryDirectory()).path,
            imageFormat: ImageFormat.JPEG,
            maxWidth: 512, // Optimize edilmiş boyut
            quality: 75,
          );
          _thumbnailPath = fileName;
        } catch (e) {
          debugPrint('Thumbnail oluşturulamadı: $e');
        }
      }

      setState(() {
        _mediaType = 'video';
        _selectedMedia = [picked]; // Video tekil olur genelde
      });
    }
  }

  // Metin değiştiğinde etiket kontrolü
  void _onTextChanged(String text) {
    final selection = _contentController.selection;
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
    // if (query.isEmpty) return; 
    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) return;

    // Takip edilenlerde kullanıcı bul
    final users = await ref.read(followServiceProvider).searchInFollowList(
      userId: currentUser.$id, 
      type: 'following', 
      query: query
    );
    
    if (mounted) {
      setState(() {
        _mentionSuggestions = users;
      });
    }
  }

  void _selectMention(String username) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    
    final textBeforeCursor = text.substring(0, selection.baseOffset);
    
    // Son kelimenin (etiketin) başlangıcını bul (boşluk veya satır başı)
    final lastWhitespace = textBeforeCursor.lastIndexOf(RegExp(r'\s'));
    final start = lastWhitespace == -1 ? 0 : lastWhitespace + 1;

    final newText = text.replaceRange(start, selection.baseOffset, '@$username ');

    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + username.length + 2), // @ + user + space
    );

    setState(() {
      _showMentions = false;
      _mentionSuggestions = [];
    });
  }

  Future<void> _submit() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final currentUser = ref.read(currentUserProvider).value;
      if (currentUser == null) {
        throw Exception('Kullanıcı bulunamadı');
      }

      // 🔹 TAGLER
      final List<String> tags = [];
      if (_postType == 1) {
        tags.add('help');
        tags.add(_selectedHelpCategory);
      }

      // 🔹 MEDIA FILES
      List<InputFile> mediaFiles = [];
      if (_selectedMedia.isNotEmpty) {
        for (var file in _selectedMedia) {
          mediaFiles.add(await MediaService.createInputFile(file));
        }
      }

      // 🔹 Thumbnail Hazırla
      InputFile? thumbnailInput;
      if (_thumbnailPath != null) {
        thumbnailInput = InputFile.fromPath(path: _thumbnailPath!, filename: 'thumbnail.jpg');
      }

      // 🔹 Profil verisini çek (University ID için)
      // Auth User (currentUser) sadece ID sağlar. Detaylar userDocumentProvider'da.
      // DÜZELTME: userDocumentProvider yerine currentUserProfileProvider kullanıyoruz.
      // Çünkü Document ID ile Auth ID her zaman aynı olmayabilir.
      final userProfile = await ref.read(currentUserProfileProvider.future);
      
      if (userProfile == null) {
        throw Exception('Kullanıcı profili bulunamadı. İnternet bağlantınızı kontrol edin.');
      }

      final universityId = userProfile['university'] as String?;

      if (universityId == null || universityId.isEmpty) {
        // Kullanıcıya daha net bir hata mesajı ve yönlendirme önerisi
        throw Exception('Profilinizde üniversite bilgisi eksik. Lütfen profil ayarlarından üniversitenizi seçin.');
      }

      //  KRİTİK: universityId EKLENDİ
      await ref.read(postServiceProvider).createPost(
        userId: currentUser.$id,
        universityId: universityId,
        content: content,
        mediaFiles: mediaFiles,
        mediaType: _mediaType,
        tags: tags,
        thumbnailFile: thumbnailInput, // 🆕 Thumbnail gönderiliyor
      );

      // 🔄 UI'ı yenilemek için ilgili provider'ları invalidate et
      ref.invalidate(feedPostsProvider);
      ref.invalidate(userPostsProvider(currentUser.$id));
      // Not: postsCount'u da güncellemek için userProvider'ı da invalidate edebiliriz.
      // Bu, sayacın backend'de (örn. cloud function ile) güncellendiğini varsayar.
      ref.invalidate(userProvider(currentUser.$id));

      if (!mounted) return;

      await CustomPopup.showSuccess(
        context: context,
        title: 'Süper!',
        message: 'Gönderin başarıyla paylaşıldı ve yayında.',
      );
      
      if (mounted) context.pop();
    } catch (e) {
      if (!mounted) return;
      debugPrint('Post Yükleme Hatası: $e'); // Konsola detaylı hata bas
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProfileAsync = ref.watch(currentUserProfileProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: const Text('Gönderi Oluştur'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: FilledButton(
              onPressed: _isLoading ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Paylaş', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 👤 User Avatar
                    userProfileAsync.when(
                      data: (data) {
                        final photoId = data?['photoId'] ?? data?['profileImageUrl'];
                        return CircleAvatar(
                          radius: 22,
                          backgroundColor: Colors.grey[200],
                          backgroundImage: (photoId != null)
                              ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId))
                              : null,
                          child: photoId == null ? const Icon(Icons.person, color: Colors.grey) : null,
                        );
                      },
                      loading: () => const CircleAvatar(radius: 22, backgroundColor: Colors.transparent),
                      error: (_, __) => const CircleAvatar(radius: 22, child: Icon(Icons.person)),
                    ),
                    const SizedBox(width: 12),
                    
                    // 📝 Content & Options
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Post Type Chips
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildTypeChip(0, 'Genel', Icons.public),
                                const SizedBox(width: 8),
                                _buildTypeChip(1, 'Yardım', Icons.volunteer_activism),
                              ],
                            ),
                          ),
                          
                          // Help Categories
                          if (_postType == 1) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _helpCategories.map((cat) {
                                final isSelected = _selectedHelpCategory == cat;
                                return FilterChip(
                                  label: Text(cat),
                                  selected: isSelected,
                                  onSelected: (_) => setState(() => _selectedHelpCategory = cat),
                                  selectedColor: AppColors.primaryGreen.withOpacity(0.1),
                                  checkmarkColor: AppColors.primaryGreen,
                                  labelStyle: TextStyle(
                                    color: isSelected ? AppColors.primaryGreen : Colors.grey,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  backgroundColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    side: BorderSide(
                                      color: isSelected ? AppColors.primaryGreen : Colors.grey.withOpacity(0.3),
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                  visualDensity: VisualDensity.compact,
                                );
                              }).toList(),
                            ),
                          ],

                          const SizedBox(height: 16),

                          // Text Input
                          TextField(
                            controller: _contentController,
                            onChanged: _onTextChanged,
                            maxLines: null,
                            minLines: 3,
                            autofocus: true,
                            decoration: InputDecoration(
                              hintText: _postType == 0 ? 'Neler oluyor?' : 'Hangi konuda yardıma ihtiyacın var?',
                              hintStyle: TextStyle(color: Colors.grey.withOpacity(0.6), fontSize: 18),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                            style: const TextStyle(fontSize: 18),
                          ),

                          const SizedBox(height: 16),

                          // Media Preview
                          if (_selectedMedia.isNotEmpty)
                            SizedBox(
                              height: 200,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _selectedMedia.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final file = _selectedMedia[index];
                                  return Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: _mediaType == 'video'
                                            ? Container(
                                                height: 200,
                                                width: 150,
                                                color: Colors.black87, // Video için siyah arka plan
                                              )
                                            : (kIsWeb
                                                ? Image.network(
                                                    file.path,
                                                    height: 200,
                                                    width: 200,
                                                    fit: BoxFit.cover,
                                                  )
                                                : Image.file(
                                                    File(file.path),
                                                    height: 200,
                                                    width: 200,
                                                    fit: BoxFit.cover,
                                                  )),
                                      ),
                                      if (_mediaType == 'video')
                                        const Positioned.fill(
                                          child: Center(
                                            child: Icon(Icons.play_circle_fill, color: Colors.white, size: 48),
                                          ),
                                        ),
                                      Positioned(
                                        top: 6,
                                        right: 6,
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _selectedMedia.removeAt(index);
                                              if (_selectedMedia.isEmpty) _mediaType = 'image';
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(
                                              color: Colors.black54,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.close, color: Colors.white, size: 16),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Mention Suggestions
            if (_showMentions && _mentionSuggestions.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.1))),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _mentionSuggestions.length,
                  itemBuilder: (context, index) {
                    final user = _mentionSuggestions[index].data;
                    final photoId = user['photoId'] ?? user['profileImageUrl'];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: (photoId != null)
                            ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId))
                            : null,
                        child: photoId == null ? Text(user['displayName'][0].toUpperCase()) : null,
                      ),
                      title: Text(user['displayName']),
                      subtitle: Text('@${user['username']}'),
                      onTap: () => _selectMention(user['username']),
                    );
                  },
                ),
              ),

            // Bottom Toolbar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.1))),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _pickImages,
                    icon: const Icon(Icons.image_outlined, color: AppColors.primaryGreen),
                    tooltip: 'Galeri',
                  ),
                  IconButton(
                    onPressed: _pickCamera,
                    icon: const Icon(Icons.camera_alt_outlined, color: AppColors.primaryGreen),
                    tooltip: 'Kamera',
                  ),
                  IconButton(
                    onPressed: _pickVideo,
                    icon: const Icon(Icons.videocam_outlined, color: AppColors.primaryGreen),
                    tooltip: 'Video',
                  ),
                  const Spacer(),
                  // Character count or other indicators could go here
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(int type, String label, IconData icon) {
    final isSelected = _postType == type;
    return GestureDetector(
      onTap: () => setState(() => _postType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primaryGreen : Colors.grey.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
/*
  // Eski metodlar kaldırıldı: _buildTypeButton, _buildMediaButton
  // Yerine _buildTypeChip ve inline IconButton'lar kullanıldı.
*/
/*
                  // 🔹 MEDIA PREVIEW (CAROUSEL)
                  if (_selectedMedia.isNotEmpty)
                    Container(
                      height: 250,
                      margin: const EdgeInsets.only(bottom: 16),
                      child: PageView.builder(
                        itemCount: _selectedMedia.length,
                        controller: PageController(viewportFraction: 0.9),
                        itemBuilder: (context, index) {
                          final file = _selectedMedia[index];
                          return Stack(
                            children: [
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: Colors.black,
                                  image: _mediaType == 'image' ? DecorationImage(
                                    image: FileImage(File(file.path)),
                                    fit: BoxFit.cover,
                                  ) : null,
                                ),
                                child: _mediaType == 'video' 
                                  ? const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 64))
                                  : null,
                              ),
                              Positioned(
                                top: 8,
                                right: 16,
                                child: CircleAvatar(
                                  backgroundColor: Colors.black54,
                                  radius: 16,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                                    onPressed: () {
                                      setState(() {
                                        _selectedMedia.removeAt(index);
                                        if (_selectedMedia.isEmpty) _mediaType = 'image';
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          */
