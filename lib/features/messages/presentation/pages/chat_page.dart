import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:appwrite/models.dart' as models;
import 'package:appwrite/appwrite.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/config/appwrite_config.dart';
import '../../../auth/data/auth_providers.dart';
import '../../data/message_providers.dart';
import '../../../../services/image_upload_service.dart';
import '../../../../services/appwrite_service.dart';
import '../../../block/data/block_service.dart';
import '../widgets/story_reply_bubble.dart'; // ✅ StoryReplyBubble import edildi

class ChatPage extends ConsumerStatefulWidget {
  final String chatId;
  final String chatTitle; // Başlık için (Kullanıcı adı veya Grup adı)

  const ChatPage({
    super.key,
    required this.chatId,
    required this.chatTitle,
  });

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isUploading = false;
  bool _isSent = false; // ✨ Animasyon için durum
  models.Document? _replyMessage; // Yanıtlanan mesaj
  
  // Typing Indicator
  Timer? _typingTimer;
  StreamSubscription? _chatDocSubscription;
  StreamSubscription? _messagesSubscription; // 🔥 EKLENDİ: Mesaj dinleyicisi
  List<String> _typingUsers = [];

  // Audio Recording
  late final AudioRecorder _audioRecorder;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    // Sohbet dokümanını dinle (Yazıyor... durumu için)
    _chatDocSubscription = ref.read(messageServiceProvider).subscribeToChatDocument(widget.chatId).listen((event) {
      if (event.events.any((e) => e.endsWith('.update'))) {
        final data = event.payload;
        if (mounted) {
          setState(() {
            _typingUsers = List<String>.from(data['typingUsers'] ?? []);
          });
        }
      }
    });

    // 🔥 REALTIME DÜZELTME: Mesajları manuel dinle (Daha kararlı çalışır)
    _messagesSubscription = ref.read(messageServiceProvider).subscribeToChatMessages(widget.chatId).listen((event) {
      // Yeni mesaj geldiğinde veya silindiğinde listeyi yenile
      if (event.events.any((e) => e.endsWith('.create') || e.endsWith('.update') || e.endsWith('.delete'))) {
        ref.invalidate(chatMessagesProvider(widget.chatId));
      }
    });
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    _chatDocSubscription?.cancel();
    _messagesSubscription?.cancel(); // 🔥 EKLENDİ
    _typingTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) return;

    _messageController.clear();

    try {
      await ref.read(messageServiceProvider).sendMessage(
        chatId: widget.chatId,
        senderId: currentUser.$id,
        content: content,
        type: 'text',
        replyTo: _replyMessage?.$id,
      );
      // Scroll to bottom
      
      // 🔥 ANINDA GÜNCELLEME: Realtime beklemeden listeyi yenile
      ref.invalidate(chatMessagesProvider(widget.chatId));
      // 🔥 EKLENDİ: Mesaj listesini (MessagesPage) de yenile ki "Son Mesaj" güncellensin
      ref.invalidate(myChatsProvider);

      // ✨ Animasyonu Tetikle
      if (mounted) {
        setState(() => _isSent = true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _isSent = false);
        });
      }

      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
      setState(() => _replyMessage = null); // Yanıtı temizle
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mesaj gönderilemedi: $e')),
        );
      }
    }
  }

  Future<void> _pickAndSendMedia() async {
    final ImagePicker picker = ImagePicker();
    // Hem resim hem video seçimine izin ver
    final XFile? media = await picker.pickMedia();
    
    if (media == null) return;

    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) return;

    setState(() => _isUploading = true);

    try {
      final storage = Storage(AppwriteService.client);
      final inputFile = await MediaService.createInputFile(media);
      
      final file = await storage.createFile(
        bucketId: AppwriteConfig.storageBucketId,
        fileId: ID.unique(),
        file: inputFile,
      );

      // Dosya uzantısına göre tip belirle
      final isVideo = media.path.toLowerCase().endsWith('.mp4') || media.path.toLowerCase().endsWith('.mov');

      await ref.read(messageServiceProvider).sendMessage(
        chatId: widget.chatId,
        senderId: currentUser.$id,
        content: isVideo ? '🎥 Video' : '📷 Fotoğraf',
        type: isVideo ? 'video' : 'image',
        fileId: file.$id,
        replyTo: _replyMessage?.$id,
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles();
    
    if (result == null || result.files.isEmpty) return;
    final fileData = result.files.first;

    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) return;

    setState(() => _isUploading = true);

    try {
      final storage = Storage(AppwriteService.client);
      final inputFile = await MediaService.createInputFileFromPlatformFile(fileData);
      
      final file = await storage.createFile(
        bucketId: AppwriteConfig.storageBucketId,
        fileId: ID.unique(),
        file: inputFile,
      );

      await ref.read(messageServiceProvider).sendMessage(
        chatId: widget.chatId,
        senderId: currentUser.$id,
        content: fileData.name,
        type: 'file',
        fileId: file.$id,
        replyTo: _replyMessage?.$id,
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _sendLocation() async {
    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) return;

    setState(() => _isUploading = true);

    try {
      // İzin kontrolü
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Konum izni reddedildi');
        }
      }

      final position = await Geolocator.getCurrentPosition();
      final locationString = '${position.latitude},${position.longitude}';

      await ref.read(messageServiceProvider).sendMessage(
        chatId: widget.chatId,
        senderId: currentUser.$id,
        content: locationString,
        type: 'location',
        replyTo: _replyMessage?.$id,
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showAttachmentModal() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.image, color: Colors.purple),
              title: const Text('Fotoğraf & Video'),
              onTap: () { Navigator.pop(context); _pickAndSendMedia(); },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file, color: Colors.blue),
              title: const Text('Belge'),
              onTap: () { Navigator.pop(context); _pickAndSendFile(); },
            ),
            ListTile(
              leading: const Icon(Icons.location_on, color: Colors.red),
              title: const Text('Konum'),
              onTap: () { Navigator.pop(context); _sendLocation(); },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMap(String location) async {
    final googleMapsUrl = Uri.parse("https://www.google.com/maps/search/?api=1&query=$location");
    if (!await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Harita açılamadı')));
    }
  }

  // 🎤 Ses Kaydı Başlat
  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final path = '${directory.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() => _isRecording = true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kayıt başlatılamadı: $e')));
    }
  }

  // ⏹️ Kaydı Durdur ve Gönder
  Future<void> _stopAndSendRecording() async {
    final path = await _audioRecorder.stop();
    setState(() => _isRecording = false);

    if (path != null) {
      final currentUser = ref.read(currentUserProvider).value;
      if (currentUser == null) return;

      setState(() => _isUploading = true);
      try {
        final storage = Storage(AppwriteService.client);
        // XFile oluştur
        final inputFile = await MediaService.createInputFile(XFile(path));
        
        final file = await storage.createFile(
          bucketId: AppwriteConfig.storageBucketId,
          fileId: ID.unique(),
          file: inputFile,
        );

        await ref.read(messageServiceProvider).sendMessage(
          chatId: widget.chatId,
          senderId: currentUser.$id,
          content: '🎤 Sesli Mesaj',
          type: 'audio',
          fileId: file.$id,
          replyTo: _replyMessage?.$id,
        );
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ses gönderilemedi: $e')));
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
    }
  }

  // ❌ Kaydı İptal Et
  Future<void> _cancelRecording() async {
    await _audioRecorder.stop();
    setState(() => _isRecording = false);
  }

  // Okundu Bilgisi Göster (Sola Kaydırma)
  void _showReadReceipts(BuildContext context, List<String> readBy) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        // Gönderen (kendisi) hariç okuyanlar
        final readers = readBy.where((id) => id != ref.read(currentUserProvider).value?.$id).toList();

        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Okuyanlar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            const Divider(height: 1),
            if (readers.isEmpty)
              const Expanded(child: Center(child: Text('Henüz kimse okumadı.')))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: readers.length,
                  itemBuilder: (context, index) {
                    final userId = readers[index];
                    return Consumer(
                      builder: (context, ref, _) {
                        final userAsync = ref.watch(userProfileProvider(userId));
                        return userAsync.when(
                          data: (user) {
                            final name = user?['displayName'] ?? 'Kullanıcı';
                            final photoId = user?['photoId'] ?? user?['profileImageUrl'];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: photoId != null 
                                    ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId)) 
                                    : null,
                                child: photoId == null ? Text(name[0]) : null,
                              ),
                              title: Text(name),
                              // Okunma zamanı eklenebilir (Veritabanında tutuluyorsa)
                            );
                          },
                          loading: () => const ListTile(title: Text('Yükleniyor...')),
                          error: (_,__) => const SizedBox.shrink(),
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

  // Metin değiştiğinde çalışır
  void _onTextChanged(String text) {
    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) return;

    // Debounce: Sürekli istek atmamak için timer kullan
    if (_typingTimer?.isActive ?? false) _typingTimer!.cancel();
    
    ref.read(messageServiceProvider).updateTypingStatus(widget.chatId, currentUser.$id, true);

    _typingTimer = Timer(const Duration(milliseconds: 1500), () {
      ref.read(messageServiceProvider).updateTypingStatus(widget.chatId, currentUser.$id, false);
    });
    setState(() {}); // UI güncelle (Mikrofon/Gönder butonu değişimi için)
  }

  // Tarih Formatlayıcı (Bugün, Dün, vb.)
  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) {
      return 'Bugün';
    } else if (messageDate == yesterday) {
      return 'Dün';
    } else {
      return DateFormat('d MMMM yyyy', 'tr').format(date);
    }
  }

  // İki tarih aynı gün mü?
  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year && date1.month == date2.month && date1.day == date2.day;
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider).value;
    final messagesAsync = ref.watch(chatMessagesProvider(widget.chatId));

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Consumer(
          builder: (context, ref, _) {
            // Sohbet detaylarını çek (Resim ve ID'ler için)
            final chatAsync = ref.watch(myChatsProvider);
            
            return chatAsync.when(
              data: (chats) {
                // Mevcut sohbeti bul
                models.Document? chat;
                try {
                  chat = chats.firstWhere((c) => c.$id == widget.chatId);
                } catch (_) {
                  chat = null;
                }

                if (chat == null) {
                  return Text(widget.chatTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold));
                }

                final data = chat.data;
                final isGroup = data['type'] == 'group'; 
                // final mutedBy = List<String>.from(data['mutedBy'] ?? []); // HATA: Bu alan veritabanında yok.
                // final isMuted = mutedBy.contains(currentUser?.$id);
                
                String? otherUserId;
                if (!isGroup) {
                  final participants = List<String>.from(data['participantIds'] ?? []);
                  otherUserId = participants.firstWhere(
                    (id) => id != currentUser?.$id,
                    orElse: () => '',
                  );
                }

                // Birebir sohbet için kullanıcı verisini çek
                final otherUserAsync = (!isGroup && otherUserId != null && otherUserId.isNotEmpty)
                    ? ref.watch(userProfileProvider(otherUserId))
                    : const AsyncValue.data(null);

                return otherUserAsync.when(
                  data: (otherUserData) {
                    String displayTitle = widget.chatTitle;
                    String? displayImageId;

                    if (isGroup) {
                      displayTitle = data['groupName'] ?? widget.chatTitle;
                      displayImageId = data['groupImageId'];
                    } else if (otherUserData != null) {
                      displayTitle = otherUserData['displayName'] ?? widget.chatTitle;
                      displayImageId = otherUserData['photoId'] ?? otherUserData['profileImageUrl'];
                    }

                    return InkWell(
                      onTap: () {
                        if (isGroup) {
                          context.push('/group-info/${widget.chatId}');
                        } else if (otherUserId != null && otherUserId.isNotEmpty) {
                          context.push('/chat-info/${widget.chatId}/$otherUserId');
                        }
                      },
                  child: Container( // Row yerine Container ile sarmalayıp padding verelim
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: isGroup ? Colors.orange.shade100 : Colors.grey.shade200,
                            backgroundImage: displayImageId != null 
                                ? CachedNetworkImageProvider(MediaService.getFileUrl(displayImageId)) 
                                : null,
                            child: displayImageId == null 
                                ? Icon(isGroup ? Icons.groups : Icons.person, size: 20, color: Colors.grey) 
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayTitle,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                // ⌨️ YAZIYOR GÖSTERGESİ
                                if (_typingUsers.isNotEmpty && !_typingUsers.contains(currentUser?.$id))
                                  const Text(
                                    'Yazıyor...',
                                    style: TextStyle(fontSize: 12, color: AppColors.primaryGreen, fontStyle: FontStyle.italic),
                                  )
                                else if (isGroup)
                                  const Text(
                                    'Grup bilgisi için dokunun',
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                  )
                                else
                                  const Text(
                                    'Kişi bilgisi için dokunun',
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                  },
                  loading: () => Text(widget.chatTitle),
                  error: (_,__) => Text(widget.chatTitle),
                );
              },
              loading: () => Text(widget.chatTitle),
              error: (_,__) => Text(widget.chatTitle),
            );
          },
        ),
        actions: [
          // 3 NOKTA MENÜSÜ
          Consumer(
            builder: (context, ref, _) {
              final chatAsync = ref.watch(myChatsProvider);
              return chatAsync.when(
                data: (chats) {
                  if (chats.isEmpty) return const SizedBox.shrink();
                  
                  models.Document? chat;
                  try {
                    chat = chats.firstWhere((c) => c.$id == widget.chatId);
                  } catch (_) {
                    return const SizedBox.shrink();
                  }

                  final isGroup = chat.data['type'] == 'group'; 
                  // final mutedBy = List<String>.from(chat.data['mutedBy'] ?? []); // HATA: Bu alan veritabanında yok.
                  // final isMuted = mutedBy.contains(currentUser?.$id);

                  // Karşı tarafın ID'sini bul (Engelleme için)
                  String? targetUserId;
                  if (!isGroup) {
                    targetUserId = (chat.data['participantIds'] as List).firstWhere((id) => id != currentUser?.$id, orElse: () => null);
                  }

                  return PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'delete') {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: Text(isGroup ? 'Gruptan Ayrıl' : 'Sohbeti Sil'),
                            content: Text(isGroup ? 'Gruptan ayrılmak istiyor musunuz?' : 'Sohbeti silmek istiyor musunuz?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('İptal')),
                              TextButton(onPressed: () => Navigator.pop(c, true), child: Text(isGroup ? 'Ayrıl' : 'Sil', style: const TextStyle(color: Colors.red))),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          if (isGroup) {
                            await ref.read(messageServiceProvider).leaveGroup(chatId: widget.chatId, userId: currentUser!.$id, userName: currentUser.name);
                          } else {
                            await ref.read(messageServiceProvider).deleteChat(widget.chatId);
                          }
                          // 🔥 DÜZELTME: context.go yerine pop kullanıldı.
                          // Böylece mesaj listesine geri dönülür ve alt bar/geri tuşu kaybolmaz.
                          if (mounted) context.pop(); 
                        }
                      } else if (value == 'block' && targetUserId != null) {
                        // 🚫 ENGELLEME İŞLEMİ
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Kullanıcıyı Engelle'),
                            content: const Text('Bu kullanıcıyı engellemek istediğine emin misin? Artık sana mesaj atamayacak.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('İptal')),
                              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Engelle', style: TextStyle(color: Colors.red))),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          await ref.read(blockServiceProvider).blockUser(currentUserId: currentUser!.$id, targetUserId: targetUserId);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kullanıcı engellendi.')));
                            context.pop(); // Sohbetten çık
                          }
                        }
                      }
                    },
                    itemBuilder: (context) => [
                      // PopupMenuItem(value: 'mute', child: Text(isMuted ? 'Sesi Aç' : 'Sessize Al')),
                      if (!isGroup) // Sadece birebir sohbette engelleme olur
                        const PopupMenuItem(value: 'block', child: Text('Engelle', style: TextStyle(color: Colors.red))),
                      PopupMenuItem(value: 'delete', child: Text(isGroup ? 'Gruptan Ayrıl' : 'Sohbeti Sil', style: const TextStyle(color: Colors.red))),
                    ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_,__) => const SizedBox.shrink(),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Hata: $e')),
              data: (messages) {
                if (messages.isEmpty) {
                  return const Center(child: Text('Henüz mesaj yok.'));
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true, // En yeni mesaj en altta (ListView reverse ile çalışır)
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final data = msg.data;
                    final type = data['type'] ?? data['messageType'] ?? 'text'; // ✅ Type öncelikli okuma
                    final fileId = data['fileId'];
                    final isMe = data['senderId'] == currentUser?.$id;
                    final content = data['content'];
                    final createdAt = DateTime.parse(msg.$createdAt);
                    final readBy = List.from(data['readBy'] ?? []);
                    final isRead = readBy.length > 1; // Kendisi hariç biri okumuş mu?

                    // --- TARİH GRUPLAMA MANTIĞI ---
                    bool showDateHeader = false;
                    if (index == messages.length - 1) {
                      // Listenin sonu (en eski mesaj) -> Tarih göster
                      showDateHeader = true;
                    } else {
                      final nextMsg = messages[index + 1];
                      final nextCreatedAt = DateTime.parse(nextMsg.$createdAt);
                      if (!_isSameDay(createdAt, nextCreatedAt)) showDateHeader = true;
                    }

                    // 🔔 SİSTEM MESAJI (Ortada gri yazı)
                    if (type == 'system' || data['senderId'] == 'system') {
                      return Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(content, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                        ),
                      );
                    }

                    // ✨ STORY REPLY BUBBLE ENTEGRASYONU
                    if (type == 'story_reply') {
                      final replyBubble = StoryReplyBubble(message: msg, isMe: isMe);
                      
                      if (showDateHeader) {
                        return Column(
                          children: [
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 16),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(_formatDateHeader(createdAt), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
                            ),
                            replyBubble,
                          ],
                        );
                      }
                      return replyBubble;
                    }

                    final messageBubble = Dismissible(
                      key: Key(msg.$id),
                      direction: isMe ? DismissDirection.horizontal : DismissDirection.startToEnd,
                      confirmDismiss: (direction) async {
                        if (direction == DismissDirection.startToEnd) {
                          // SAĞA KAYDIRMA -> YANITLA
                          setState(() {
                            _replyMessage = msg;
                          });
                          _focusNode.requestFocus();
                          return false; // Silinmesini engelle
                        } else if (direction == DismissDirection.endToStart && isMe) {
                          // SOLA KAYDIRMA -> OKUNDU BİLGİSİ (Sadece kendi mesajım için)
                          _showReadReceipts(context, List<String>.from(data['readBy'] ?? []));
                          return false;
                        }
                        return false;
                      },
                      background: Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(left: 20),
                        child: const Icon(Icons.reply, color: Colors.grey),
                      ),
                      secondaryBackground: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.info_outline, color: Colors.blue),
                      ),
                      // 🔥 HİZALAMA DÜZELTME: Align widget'ı eklendi
                      child: Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isMe ? const Color(0xFFDCF8C6) : Colors.white, // WhatsApp renkleri
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(12),
                              topRight: const Radius.circular(12),
                              bottomLeft: isMe ? const Radius.circular(12) : Radius.zero,
                              bottomRight: isMe ? Radius.zero : const Radius.circular(12),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              )
                            ],
                          ),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 🆕 GRUP İÇİN GÖNDEREN İSMİ (Sadece gelen mesajlarda)
                              if (!isMe)
                                Consumer(
                                  builder: (context, ref, _) {
                                    final userAsync = ref.watch(userProfileProvider(data['senderId']));
                                    return userAsync.when(
                                      data: (user) => Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: Text(
                                          user?['displayName'] ?? 'Kullanıcı',
                                          style: TextStyle(
                                            color: Colors.orange[800],
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      loading: () => const SizedBox.shrink(),
                                      error: (_,__) => const SizedBox.shrink(),
                                    );
                                  },
                                ),

                              if ((type == 'image' || type == 'video') && fileId != null)
                                GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context, 
                                      MaterialPageRoute(builder: (_) => _FullScreenImageViewer(imageUrl: MediaService.getFileUrl(fileId)))
                                    );
                                  },
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: CachedNetworkImage(
                                          imageUrl: MediaService.getFileUrl(fileId), // Video için thumbnail gerekebilir, şimdilik direkt URL
                                          placeholder: (context, url) => const CircularProgressIndicator(),
                                          errorWidget: (context, url, error) => Container(
                                            height: 200, width: 200, color: Colors.black12,
                                            child: Icon(type == 'video' ? Icons.videocam : Icons.broken_image),
                                          ),
                                          height: 200,
                                          width: 200,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      if (type == 'video')
                                        const CircleAvatar(
                                          backgroundColor: Colors.black54,
                                          child: Icon(Icons.play_arrow, color: Colors.white),
                                        ),
                                    ],
                                  ),
                                )
                              else if (type == 'file')
                                GestureDetector(
                                  onTap: () => launchUrl(Uri.parse(MediaService.getFileUrl(fileId!)), mode: LaunchMode.externalApplication),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.insert_drive_file, color: Colors.orange),
                                        const SizedBox(width: 8),
                                        Flexible(child: Text(content, style: const TextStyle(decoration: TextDecoration.underline))),
                                      ],
                                    ),
                                  ),
                                )
                              else if (type == 'location')
                                GestureDetector(
                                  onTap: () => _openMap(content),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(Icons.location_on, color: Colors.red, size: 16),
                                          SizedBox(width: 4),
                                          Text('Konum Paylaşıldı', style: TextStyle(fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                      Text(content, style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline)),
                                    ],
                                  ),
                                )
                              else if (type == 'audio' && fileId != null)
                                _AudioPlayerBubble(url: AppwriteService.getFileViewUrl(fileId), isMe: isMe)
                              else
                                Text(
                                  content,
                                  style: const TextStyle(color: Colors.black87, fontSize: 16),
                                ),
                              const SizedBox(height: 4),
                              
                              // SAAT VE TİK (WhatsApp Style)
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      DateFormat('HH:mm').format(createdAt),
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 11,
                                      ),
                                    ),
                                    if (isMe) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.done_all, 
                                        size: 16, 
                                        color: isRead ? Colors.blue : Colors.grey[500]
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );

                    // Tarih başlığı varsa Column içinde döndür
                    if (showDateHeader) {
                      return Column(
                        children: [
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 16),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(_formatDateHeader(createdAt), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
                          ),
                          messageBubble,
                        ],
                      );
                    }
                    
                    return messageBubble;
                  },
                );
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    // Kayıt Modu UI
    if (_isRecording) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.grey[100],
        child: SafeArea(
          child: Row(
            children: [
              const Icon(Icons.mic, color: Colors.red, size: 24),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Kaydediliyor...',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.grey),
                onPressed: _cancelRecording,
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: AppColors.primaryGreen,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: _stopAndSendRecording,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // YANITLAMA PANELİ
        if (_replyMessage != null)
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey[100],
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 40,
                  color: AppColors.primaryGreen,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Yanıtlanıyor', style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold, fontSize: 12)),
                      Text(
                        _replyMessage!.data['content'] ?? 'Medya',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => setState(() => _replyMessage = null),
                ),
              ],
            ),
          ),
        
        // MESAJ GİRİŞ ALANI
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, -2),
            blurRadius: 5,
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.add, color: AppColors.primaryGreen),
              onPressed: _isUploading ? null : _showAttachmentModal,
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(24),
                ),
                            child: TextField(
              controller: _messageController,
              focusNode: _focusNode,
              onChanged: _onTextChanged,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              minLines: 1,
              maxLines: null,
              decoration: const InputDecoration(
                hintText: 'Mesaj yazın...',
                border: InputBorder.none,
              ),
            ),
            ),),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: AppColors.primaryGreen,
              child: _isUploading
                ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : _isSent 
                  ? const Icon(Icons.check, color: Colors.white, size: 20) // ✨ Tik İkonu
                  : _messageController.text.trim().isEmpty
                    ? IconButton(
                        icon: const Icon(Icons.mic, color: Colors.white, size: 20),
                        onPressed: _startRecording,
                      )
                    : AnimatedSwitcher( // ✨ Animasyonlu Geçiş
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                        child: IconButton(
                          key: const ValueKey('send'),
                          icon: const Icon(Icons.send, color: Colors.white, size: 20),
                          onPressed: _sendMessage,
                        ),
                      ),
            ),
          ],
        ),
      ),
        ),
      ],
    );
  }
}

/// 🎵 Sesli Mesaj Oynatıcı Widget'ı
class _AudioPlayerBubble extends StatefulWidget {
  final String url;
  final bool isMe;

  const _AudioPlayerBubble({required this.url, required this.isMe});

  @override
  State<_AudioPlayerBubble> createState() => _AudioPlayerBubbleState();
}

class _AudioPlayerBubbleState extends State<_AudioPlayerBubble> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    _audioPlayer.onDurationChanged.listen((newDuration) {
      if (mounted) setState(() => _duration = newDuration);
    });
    _audioPlayer.onPositionChanged.listen((newPosition) {
      if (mounted) setState(() => _position = newPosition);
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
          color: widget.isMe ? Colors.white : AppColors.primaryGreen,
          iconSize: 32,
          onPressed: () async {
            if (_isPlaying) {
              await _audioPlayer.pause();
            } else {
              await _audioPlayer.play(UrlSource(widget.url));
            }
          },
        ),
        Text(
          '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
          style: TextStyle(fontSize: 12, color: widget.isMe ? Colors.white : Colors.black87),
        ),
      ],
    );
  }
}

class _FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  const _FullScreenImageViewer({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
      body: Center(
        child: InteractiveViewer(
          child: CachedNetworkImage(imageUrl: imageUrl),
        ),
      ),
    );
  }
}
