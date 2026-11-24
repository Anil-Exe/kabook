import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import '../../../core/config/appwrite_config.dart';
import '../../follow/data/follow_service.dart';
import '../../block/data/block_service.dart';
import '../../notifications/data/notification_service.dart';

class MessageService {
  final Databases _databases;
  final Realtime _realtime;
  final FollowService _followService;
  final BlockService _blockService;
  final NotificationService _notificationService;

  MessageService({
    required Databases databases,
    required Realtime realtime,
    required FollowService followService,
    required BlockService blockService,
    required NotificationService notificationService,
  })  : _databases = databases,
        _realtime = realtime,
        _followService = followService,
        _blockService = blockService,
        _notificationService = notificationService;

  /// 🆕 1. Sohbet Oluştur (İzinlerle Birlikte)
  Future<models.Document> createChat({
    required List<String> participantIds,
    required String type, // 'direct' veya 'group'
    String? groupName,
    String? groupImageId,
    String? creatorId,
  }) async {
    // Birebir sohbet kontrolü (Client-side filtreleme)
    if (type == 'direct') {
      // İlk kullanıcı (genelde current user) üzerinden sohbetleri çek
      final myChats = await getUserChats(participantIds.first, status: null); // Hepsini getir
      for (var chat in myChats) {
        if (chat.data['type'] == 'direct') {
          List<dynamic> p = chat.data['participantIds'];
          // Katılımcılar aynı mı?
          if (p.length == 2 && p.contains(participantIds[0]) && p.contains(participantIds[1])) {
            return chat;
          }
        }
      }
    }

    // Mesaj İsteği Kontrolü (Sadece Direct mesajlar için)
    String status = 'active';
    if (type == 'direct' && creatorId != null) {
      final targetId = participantIds.firstWhere((id) => id != creatorId);
      
      // Hedef kullanıcı beni takip ediyor mu?
      final followDoc = await _followService.getFollowStatus(targetId, creatorId);
      final isFollowingMe = followDoc != null && followDoc.data['status'] == 'approved';

      // Eğer beni takip etmiyorsa bu bir "Mesaj İsteği"dir
      if (!isFollowingMe) {
        status = 'request';
      }
    }

    // Yeni sohbet oluştur
    return await _databases.createDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.chatsCollectionId,
      documentId: ID.unique(),
      data: {
        'type': type,
        'participantIds': participantIds,
        'adminIds': creatorId != null ? [creatorId] : [],
        'groupName': groupName,
        'groupImageId': groupImageId,
        'status': status,
        'initiatedBy': creatorId,
        'mutedBy': [], // Başlangıçta kimse sessize almadı
        'lastMessage': type == 'group' ? 'Grup oluşturuldu' : '',
        'lastMessageAt': DateTime.now().toIso8601String(),
      },
    );
  }

  /// 📜 2. Kullanıcının Sohbetlerini Getir
  /// [status] null ise hepsini, 'active' veya 'request' ise filtreleyerek getirir.
  Future<List<models.Document>> getUserChats(String userId, {String? status}) async {
    // Document Security açık olduğu için, sadece kullanıcının izinli olduğu dokümanlar gelir.
    final List<String> queries = [
      Query.contains('participantIds', userId), // 🔥 DÜZELTİLDİ: Array olduğu için contains kullanılmalı
      Query.orderDesc('lastMessageAt'),
    ];

    if (status != null) {
      queries.add(Query.equal('status', status));
    }

    final result = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.chatsCollectionId,
      queries: queries,
    );
    return result.documents;
  }

  /// 📨 3. Mesaj Gönder
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String content,
    String type = 'text',
    String? fileId,
    String? replyTo,
  }) async {
    final now = DateTime.now().toIso8601String();

    // 1. Sohbet detaylarını çek (receiverId'yi bulmak için)
    final chatDoc = await _databases.getDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.chatsCollectionId,
      documentId: chatId,
    );

    final chatData = chatDoc.data;
    final List<dynamic> participants = chatData['participantIds'] ?? [];
    
    // Alıcıyı belirle (Grup ise chatId, Birebir ise karşı taraf)
    String receiverId = chatId; 
    if (chatData['type'] == 'direct') {
      receiverId = participants.firstWhere((id) => id != senderId, orElse: () => chatId);
    }

    // 🚫 ENGEL KONTROLÜ
    if (chatData['type'] == 'direct') {
      final isBlocked = await _blockService.hasBlocked(blockerId: receiverId, blockedId: senderId);
      if (isBlocked) throw Exception('Bu kullanıcıya mesaj gönderemezsiniz.');
    }

    // ✅ MESAJ İSTEĞİNİ KABUL ETME MANTIĞI
    // Eğer sohbet 'request' durumundaysa ve mesajı atan kişi sohbeti başlatan (initiatedBy) değilse,
    // demek ki alıcı cevap veriyor -> Durumu 'active' yap.
    if (chatData['status'] == 'request') {
      final initiatedBy = chatData['initiatedBy'];
      if (initiatedBy != null && initiatedBy != senderId) {
        await _updateChatStatus(chatId, 'active');
      }
    }

    // Mesajı oluştur
    await _databases.createDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.messagesCollectionId,
      documentId: ID.unique(),
      data: {
        'chatId': chatId,
        'senderId': senderId,
        'receiverId': receiverId,
        'content': content,
        'messageType': type,
        'fileId': fileId,
        // 'replyTo': replyTo, // ❌ HATA DÜZELTME: Schema'da olmadığı için kaldırıldı
        'readBy': [senderId],
      },
    );

    // Sohbetin üst verisini güncelle
    await _databases.updateDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.chatsCollectionId,
      documentId: chatId,
      data: {
        'lastMessage': type == 'text' ? content : (type == 'image' ? '📷 Fotoğraf' : (type == 'video' ? '🎥 Video' : (type == 'audio' ? '🎤 Sesli Mesaj' : '📎 Dosya'))),
        'lastMessageAt': now,
      },
    );

    // 🔔 BİLDİRİM GÖNDER (Kendi kendine değilse)
    if (senderId != receiverId) {
      // 🔇 SESSİZE ALMA KONTROLÜ
      final mutedBy = List<String>.from(chatData['mutedBy'] ?? []);
      // Eğer alıcı (birebir sohbet) sessize aldıysa bildirim gönderme
      if (chatData['type'] == 'direct' && mutedBy.contains(receiverId)) return;

      // NOT: Mesajlar artık 'notifications' koleksiyonuna eklenmiyor (Bildirimler sayfasında görünmemesi için).
      // Sistem bildirimi (Push Notification) için Appwrite Function 'messages' koleksiyonunu dinlemelidir.
    }
  }

  /// ⚙️ Sistem Mesajı Gönder (Örn: "Ahmet gruba eklendi")
  Future<void> sendSystemMessage({
    required String chatId,
    required String content,
  }) async {
    await _databases.createDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.messagesCollectionId,
      documentId: ID.unique(),
      data: {
        'chatId': chatId,
        'senderId': 'system', // Sistem mesajı olduğunu belirtir
        'receiverId': chatId,
        'content': content,
        'messageType': 'system',
        'readBy': [],
      },
    );

    // Sohbetin son mesajını güncelle
    await _databases.updateDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.chatsCollectionId,
      documentId: chatId,
      data: {
        'lastMessage': content,
        'lastMessageAt': DateTime.now().toIso8601String(),
      },
    );
  }

  /// 🚫 Gruptan Üye Çıkar
  Future<void> removeParticipant({
    required String chatId,
    required String adminId,
    required String targetUserId,
    required String targetUserName,
  }) async {
    // 1. Sohbeti getir
    final chatDoc = await _databases.getDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.chatsCollectionId,
      documentId: chatId,
    );

    List<dynamic> participants = List.from(chatDoc.data['participantIds']);
    
    // 2. Listeden çıkar
    participants.remove(targetUserId);

    // 3. Güncelle
    await _databases.updateDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.chatsCollectionId,
      documentId: chatId,
      data: {'participantIds': participants},
    );

    // 4. Bilgi mesajı at
    await sendSystemMessage(chatId: chatId, content: '$targetUserName gruptan çıkarıldı.');
  }

  /// ➕ Gruba Üye Ekle
  Future<void> addParticipant({
    required String chatId,
    required String newUserId,
    required String newUserName,
  }) async {
    final chatDoc = await _databases.getDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.chatsCollectionId,
      documentId: chatId,
    );

    List<dynamic> participants = List.from(chatDoc.data['participantIds']);
    if (!participants.contains(newUserId)) {
      participants.add(newUserId);

      await _databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.chatsCollectionId,
        documentId: chatId,
        data: {'participantIds': participants},
      );

      await sendSystemMessage(chatId: chatId, content: '$newUserName gruba eklendi.');
    }
  }

  /// 👑 Yönetici Yetkisi Ver/Al
  Future<void> toggleGroupAdmin({
    required String chatId,
    required String targetUserId,
    required String targetUserName,
    required bool makeAdmin,
  }) async {
    final chatDoc = await _databases.getDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.chatsCollectionId,
      documentId: chatId,
    );

    List<dynamic> adminIds = List.from(chatDoc.data['adminIds'] ?? []);
    
    if (makeAdmin && !adminIds.contains(targetUserId)) {
      adminIds.add(targetUserId);
    } else if (!makeAdmin && adminIds.contains(targetUserId)) {
      adminIds.remove(targetUserId);
    }

    await _databases.updateDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.chatsCollectionId,
      documentId: chatId,
      data: {'adminIds': adminIds},
    );

    await sendSystemMessage(
      chatId: chatId, 
      content: makeAdmin ? '$targetUserName artık yönetici.' : '$targetUserName yöneticilikten alındı.'
    );
  }

  /// 👋 Gruptan Ayrıl
  Future<void> leaveGroup({
    required String chatId,
    required String userId,
    required String userName,
  }) async {
    final chatDoc = await _databases.getDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.chatsCollectionId,
      documentId: chatId,
    );

    List<dynamic> participants = List.from(chatDoc.data['participantIds']);
    participants.remove(userId);

    await _databases.updateDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.chatsCollectionId,
      documentId: chatId,
      data: {'participantIds': participants},
    );

    await sendSystemMessage(chatId: chatId, content: '$userName gruptan ayrıldı.');
  }

  /// 📥 4. Sohbet Geçmişini Getir
  Future<List<models.Document>> getMessages({
    required String chatId,
    int limit = 50,
    String? lastId,
  }) async {
    List<String> queries = [
      Query.equal('chatId', chatId),
      Query.orderDesc('\$createdAt'),
      Query.limit(limit),
    ];

    if (lastId != null) {
      queries.add(Query.cursorAfter(lastId));
    }

    final result = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.messagesCollectionId,
      queries: queries,
    );
    return result.documents;
  }

  /// 👀 5. Mesajı Okundu İşaretle
  Future<void> markMessageAsRead(String messageId, String userId) async {
    try {
      final doc = await _databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.messagesCollectionId,
        documentId: messageId,
      );

      List<dynamic> readBy = List.from(doc.data['readBy'] ?? []);
      if (!readBy.contains(userId)) {
        readBy.add(userId);
        await _databases.updateDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.messagesCollectionId,
          documentId: messageId,
          data: {'readBy': readBy},
        );
      }
    } catch (e) {
      print('Read mark error: $e');
    }
  }

  ///  6. Realtime: Sohbet Listesi Dinle
  Stream<RealtimeMessage> subscribeToUserChats(String userId) {
    return _realtime.subscribe([
      'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.chatsCollectionId}.documents'
    ]).stream;
  }

  /// 🔔 7. Realtime: Seçili Sohbetin Mesajlarını Dinle
  Stream<RealtimeMessage> subscribeToChatMessages(String chatId) {
    return _realtime.subscribe([
      'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.messagesCollectionId}.documents'
    ]).stream.where((event) {
      // 🔥 GÜVENLİK: Payload kontrolü
      final payload = event.payload;
      return payload != null && payload['chatId'] == chatId;
    });
  }

  /// 🔔 8. Realtime: Tekil Sohbet Dokümanını Dinle (Typing vb. için)
  Stream<RealtimeMessage> subscribeToChatDocument(String chatId) {
    return _realtime.subscribe([
      'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.chatsCollectionId}.documents.$chatId'
    ]).stream;
  }

  /// ⌨️ Yazıyor Durumunu Güncelle
  Future<void> updateTypingStatus(String chatId, String userId, bool isTyping) async {
    try {
      final doc = await _databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.chatsCollectionId,
        documentId: chatId,
      );
      
      List<String> typingUsers = List<String>.from(doc.data['typingUsers'] ?? []);
      bool changed = false;

      if (isTyping) {
        if (!typingUsers.contains(userId)) {
          typingUsers.add(userId);
          changed = true;
        }
      } else {
        if (typingUsers.contains(userId)) {
          typingUsers.remove(userId);
          changed = true;
        }
      }

      if (changed) {
        await _databases.updateDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.chatsCollectionId,
          documentId: chatId,
          data: {'typingUsers': typingUsers},
        );
      }
    } catch (e) {
      // Attribute yoksa sessizce geç (Uygulama çökmesin)
    }
  }

  /// 🚀 9. Birebir Sohbeti Getir veya Oluştur (Start DM)
  Future<models.Document> getOrCreateDirectChat({
    required String currentUserId,
    required String targetUserId,
  }) async {
    // 1. Mevcut sohbetleri kontrol et
    final myChats = await getUserChats(currentUserId, status: null);
    
    for (var chat in myChats) {
      if (chat.data['type'] == 'direct') {
        List<dynamic> p = chat.data['participantIds'];
        // İki ID de listede var mı?
        if (p.contains(currentUserId) && p.contains(targetUserId)) {
          return chat; // Var olan sohbeti döndür
        }
      }
    }

    // 2. Yoksa yeni oluştur
    return await createChat(
      participantIds: [currentUserId, targetUserId],
      type: 'direct',
      creatorId: currentUserId,
    );
  }

  /// ✅ Mesaj İsteğini Kabul Et (Public Wrapper)
  Future<void> acceptMessageRequest(String chatId) async {
    await _updateChatStatus(chatId, 'active');
  }

  /// 🗑️ Sohbeti Sil (İsteği Reddet veya Sohbeti Temizle)
  Future<void> deleteChat(String chatId) async {
    await _databases.deleteDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.chatsCollectionId,
      documentId: chatId,
    );
    // İsteğe bağlı: Mesajları da silebilirsin ama Appwrite cascade delete varsa gerek yok.
  }

  /// 🔄 Sohbet Durumunu Güncelle (Request -> Active)
  Future<void> _updateChatStatus(String chatId, String status) async {
    await _databases.updateDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.chatsCollectionId,
      documentId: chatId,
      data: {'status': status},
    );
  }

  /// 🔇 Sohbeti Sessize Al / Sesi Aç
  Future<void> toggleMuteChat(String chatId, String userId) async {
    final doc = await _databases.getDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.chatsCollectionId,
      documentId: chatId,
    );

    List<String> mutedBy = List<String>.from(doc.data['mutedBy'] ?? []);

    if (mutedBy.contains(userId)) {
      mutedBy.remove(userId); // Sesi Aç
    } else {
      mutedBy.add(userId); // Sessize Al
    }

    await _databases.updateDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.chatsCollectionId,
      documentId: chatId,
      data: {'mutedBy': mutedBy},
    );
  }
}
  