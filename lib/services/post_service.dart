import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import '../core/config/appwrite_config.dart';
import '../models/post_model.dart';
import 'image_upload_service.dart'; // MediaService buradan geliyor

class PostService {
  final Client _client;
  late final Databases _databases;
  late final Realtime _realtime;
  late final Storage _storage;

  PostService(this._client) {
    _databases = Databases(_client);
    _realtime = Realtime(_client);
    _storage = Storage(_client);
  }

  /// 📝 POST OLUŞTUR
  Future<void> createPost({
    required String userId,
    required String content,
    required String universityId,
    List<InputFile>? mediaFiles, // 🆕 Çoklu dosya desteği
    String mediaType = 'image', // 'image' veya 'video'
    List<String>? tags,
    InputFile? thumbnailFile, // 🆕 Thumbnail parametresi
  }) async {
    try {
      List<String> mediaIds = [];

      // 1️⃣ Medyaları Yükle (Döngü ile)
      if (mediaFiles != null && mediaFiles.isNotEmpty) {
        for (var mediaFile in mediaFiles) {
          final file = await _storage.createFile(
            bucketId: AppwriteConfig.storageBucketId,
            fileId: ID.unique(),
            file: mediaFile,
          );
          mediaIds.add(file.$id);
        print('Medya yüklendi: ${file.$id}'); // Debug log
        }
      }

      // 🆕 Thumbnail Yükle (Varsa)
      String? uploadedThumbnailId;
      if (thumbnailFile != null) {
        final file = await _storage.createFile(
          bucketId: AppwriteConfig.storageBucketId,
          fileId: ID.unique(),
          file: thumbnailFile,
        );
        uploadedThumbnailId = file.$id;
      }

      // Tags'i content'e hashtag olarak ekle (Schema hatasını önlemek için)
      String finalContent = content;
      if (tags != null && tags.isNotEmpty) {
        final tagString = tags.map((t) => '#$t').join(' ');
        finalContent = '$finalContent\n\n$tagString';
      }

      // 2️⃣ Post document
      // ❗ createdAt GÖNDERİLMİYOR. Appwrite otomatik ekler.
      final postDoc = await _databases.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.postsCollectionId,
        documentId: ID.unique(),
        data: {
          'content': finalContent,
          'userId': userId,
          'university': universityId,
          // ️ REELS HATA ÇÖZÜMÜ: 
          // Video yüklerken imageId alanına video ID'sini ASLA yazma.
          // Eğer thumbnail yoksa null olsun. CachedNetworkImage videoyu indirmeye çalışıp hata vermesin.
          'imageId': uploadedThumbnailId ?? (mediaType == 'image' && mediaIds.isNotEmpty ? mediaIds.first : null),
          'mediaIds': mediaIds, // ✅ Çoklu medya ID'leri
          'mediaType': mediaType, // ✅ Medya tipi (image/video)
          'likes': <String>[],
          'likesCount': 0,
          'commentsCount': 0,
          'sharesCount': 0,
          'repostsCount': 0,
          // 🆕 Yeni Post Başlangıç Değerleri
          'score': 0,
          'lastActiveAt': DateTime.now().toIso8601String(), // Oluşturulduğu an aktiftir
          // 'createdAt': ... ❌ ASLA GÖNDERME
        },
        permissions: [
          Permission.read(Role.any()),
          Permission.update(Role.user(userId)),
          Permission.delete(Role.user(userId)),
        ],
      );

      // 🔔 Etiketlenen Kullanıcılara Bildirim Gönder (@username)
      final mentionRegex = RegExp(r"@([a-zA-Z0-9_.-]+)");
      final matches = mentionRegex.allMatches(finalContent);
      
      if (matches.isNotEmpty) {
        // Gönderen kişinin adını al
        String senderName = 'Bir kullanıcı';
        try {
          final senderDoc = await _databases.getDocument(
            databaseId: AppwriteConfig.databaseId,
            collectionId: AppwriteConfig.usersCollectionId,
            documentId: userId,
          );
          senderName = senderDoc.data['displayName'] ?? senderName;
        } catch (_) {}

        for (final match in matches) {
          final username = match.group(1);
          if (username != null) {
            // Username'den User ID bul
            final userRes = await _databases.listDocuments(
              databaseId: AppwriteConfig.databaseId,
              collectionId: AppwriteConfig.usersCollectionId,
              queries: [Query.equal('username', username), Query.limit(1)],
            );

            if (userRes.documents.isNotEmpty) {
              final targetUserId = userRes.documents.first.data['userId'];
              
              // Kendini etiketlediyse atla
              if (targetUserId != userId) {
                await _databases.createDocument(
                  databaseId: AppwriteConfig.databaseId,
                  collectionId: AppwriteConfig.notificationsCollectionId,
                  documentId: ID.unique(),
                  data: {
                    'toUserId': targetUserId,
                    'fromUserId': userId,
                    'type': 'mention',
                    'eventId': postDoc.$id,
                    'content': '$senderName bir gönderide senden bahsetti: "$content"',
                    'status': 'unread',
                    'isRead': false,
                  },
                );
              }
            }
          }
        }
      }
    } on AppwriteException catch (e) {
      print('Appwrite Hatası: ${e.code} - ${e.message}'); // Detaylı hata logu
      throw Exception(e.message ?? 'Post paylaşılırken hata oluştu');
    }
  }

  /// 🗑️ DELETE POST
  Future<void> deletePost(String postId) async {
    try {
      // 1. Postu getir (Görsel ID'sini almak için)
      final doc = await _databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.postsCollectionId,
        documentId: postId,
      );

      // 🆕 Tüm medyaları sil
      final mediaIds = List<String>.from(doc.data['mediaIds'] ?? []);
      // Eğer mediaIds boşsa ama imageId varsa onu da ekle (eski postlar için)
      if (mediaIds.isEmpty && doc.data['imageId'] != null) {
        mediaIds.add(doc.data['imageId']);
      }

      for (var id in mediaIds) {
        try {
          await _storage.deleteFile(
            bucketId: AppwriteConfig.storageBucketId,
            fileId: id,
          );
        } catch (_) {}
      }
    } catch (_) {} // Hata olsa bile (örn. post zaten yok) silmeye çalış

    await _databases.deleteDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.postsCollectionId,
      documentId: postId,
    );
  }

  /// ❤️ LIKE / UNLIKE
  Future<void> toggleLike(String postId, String userId) async {
    final post = await _databases.getDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.postsCollectionId,
      documentId: postId,
    );

    final likes = List<String>.from(post.data['likes'] ?? []);
    bool isLiked = false;

    if (likes.contains(userId)) {
      likes.remove(userId);
    } else {
      likes.add(userId);
      isLiked = true;
    }

    try {
      await _databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.postsCollectionId,
        documentId: postId,
        data: {
          'likes': likes,
          'likesCount': likes.length,
          'lastActiveAt': DateTime.now().toIso8601String(), // 🟢 Etkileşim oldu, yukarı taşı
        },
      );
    } catch (e) {
      print('Post begeni guncellenemedi (yetki hatasi olabilir): $e');
    }

    // � Bildirim Gönder
    if (isLiked && post.data['userId'] != userId) {
      try {
        // Beğenen kişinin adını al
        String senderName = 'Bir kullanıcı';
        try {
          final senderDoc = await _databases.getDocument(
            databaseId: AppwriteConfig.databaseId,
            collectionId: AppwriteConfig.usersCollectionId,
            documentId: userId,
          );
          senderName = senderDoc.data['displayName'] ?? senderName;
        } catch (_) {}

        await _databases.createDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.notificationsCollectionId,
          documentId: ID.unique(),
          data: {
            'toUserId': post.data['userId'],
            'fromUserId': userId,
            'type': 'like',
            'eventId': postId,
            'content': '$senderName gönderini beğendi.',
            'status': 'unread',
            'isRead': false,
          },
        );
      } catch (e) {
        print('Post like bildirim hatası: $e');
      }
    }
  }

  /// 🔁 REPOST
  Future<void> repost(Post originalPost, String userId, String universityId) async {
    final existing = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.postsCollectionId,
      queries: [
        Query.equal('originalPostId', originalPost.id),
        Query.equal('repostUserId', userId),
      ],
    );

    if (existing.total > 0) {
      throw Exception('Bu gönderiyi zaten paylaştınız.');
    }

    await _databases.createDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.postsCollectionId,
      documentId: ID.unique(),
      data: {
        'userId': userId,
        'content': originalPost.content,
        'imageId': originalPost.imageId,
        'mediaIds': originalPost.mediaIds, // ✅ Repost için medya ID'leri
        'mediaType': originalPost.mediaType, // ✅ Repost için medya tipi
        'originalPostId': originalPost.id,
        'repostUserId': userId,
        'university': universityId,
        'likes': <String>[],
        'likesCount': 0,
        'commentsCount': 0,
        'sharesCount': 0,
        'repostsCount': 0,
        'score': 0,
        'lastActiveAt': DateTime.now().toIso8601String(),
      },
      permissions: [
        Permission.read(Role.any()),
        Permission.update(Role.user(userId)),
        Permission.delete(Role.user(userId)),
      ],
    );

    // Orijinal post etkileşim sayaçlarını güncelle (Puanlama algoritması artık backend'de)
    try {
      await _databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.postsCollectionId,
        documentId: originalPost.id,
        data: {
          'repostsCount': originalPost.repostsCount + 1,
          'lastActiveAt': DateTime.now().toIso8601String(), // 🟢 Etkileşim oldu, yukarı taşı
        },
      );
    } catch (e) {
      print('Repost sayac guncellenemedi (yetki hatasi olabilir): $e');
    }

    // 🔔 Bildirim Gönder (Repost)
    if (originalPost.userId != userId) {
      try {
        // Repost yapan kişinin adını al
        String senderName = 'Bir kullanıcı';
        try {
          final senderDoc = await _databases.getDocument(
            databaseId: AppwriteConfig.databaseId,
            collectionId: AppwriteConfig.usersCollectionId,
            documentId: userId,
          );
          senderName = senderDoc.data['displayName'] ?? senderName;
        } catch (_) {}

        await _databases.createDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.notificationsCollectionId,
          documentId: ID.unique(),
          data: {
            'toUserId': originalPost.userId,
            'fromUserId': userId,
            'type': 'repost',
            'eventId': originalPost.id,
            'content': '$senderName gönderini paylaştı.',
            'status': 'unread',
            'isRead': false,
          },
        );
      } catch (e) {
        print('Repost notification error: $e');
      }
    }
  }

  /// 🔁 REPOSTLARI GETİR
  Future<List<models.Document>> getReposts(String postId) async {
    final res = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.postsCollectionId,
      queries: [
        Query.equal('originalPostId', postId),
        Query.orderDesc('\$createdAt'),
      ],
    );
    return res.documents;
  }

  /// ↩️ UN-REPOST (Repost Geri Al)
  Future<void> unrepost(String originalPostId, String userId) async {
    // 1. Repost dokümanını bul
    final existing = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.postsCollectionId,
      queries: [
        Query.equal('originalPostId', originalPostId),
        Query.equal('repostUserId', userId),
      ],
    );

    if (existing.total == 0) {
      throw Exception('Bu gönderiyi zaten paylaşmamışsınız.');
    }

    final repostDoc = existing.documents.first;

    // 2. Repost dokümanını sil
    await _databases.deleteDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.postsCollectionId,
      documentId: repostDoc.$id,
    );

    // 3. Orijinal postun sayaçlarını güncelle
    try {
      final originalPostDoc = await _databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.postsCollectionId,
        documentId: originalPostId,
      );

      final currentReposts = originalPostDoc.data['repostsCount'] ?? 0;
      if (currentReposts > 0) {
        await _databases.updateDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.postsCollectionId,
          documentId: originalPostId,
          data: {
            'repostsCount': currentReposts - 1,
          },
        );
      }
    } catch (e) {
      print('Orijinal post güncellenemedi: $e');
    }

    // 4. Bildirimi sil (Opsiyonel)
    // Bildirim silme işlemi NotificationService üzerinden veya manuel yapılabilir.
  }

  /// 📥 POST LİSTESİ
  Future<List<Post>> getPosts() async {
    final res = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.postsCollectionId,
      queries: [
        Query.orderDesc('score'), // 🧠 Yeni Algoritma
        Query.orderDesc('\$createdAt') // Eşitlik durumunda yenisi üstte
      ],
    );

    return res.documents
        .map((d) => Post.fromMap(d.toMap())).toList();
  }

  /// 🔍 FİLTRELİ POST LİSTESİ (Ana Sayfa İçin)
  Future<List<Post>> getFilteredPosts({
    required String currentUniversityId,
    required bool isMyUniversity, // true: Üniversiteniz, false: Tüm Üniversiteler
    required bool isFollowingOnly, // true: Takip Edilenler, false: Herkes
    required List<String> followingIds,
    String? mediaType, // 🆕 Medya türüne göre filtreleme (video/image)
  }) async {
    List<String> queries = [
      Query.orderDesc('score'), // 🧠 Yeni Algoritma
      Query.orderDesc('\$createdAt'),
    ];

    // 1. Üniversite Filtresi
    if (isMyUniversity) {
      // Sadece kendi üniversitem
      queries.add(Query.equal('university', currentUniversityId));
    }
    // else durumunda (isMyUniversity == false) hiçbir filtre eklemiyoruz.
    // Böylece "Tümü" seçildiğinde hem kendi üniversiteniz hem de diğerleri gelir.

    // 2. Takip Filtresi
    if (isFollowingOnly) {
      if (followingIds.isEmpty) {
        // Kimseyi takip etmiyorsa boş liste dön
        return [];
      }
      // Sadece takip ettiklerim (userId IN list)
      queries.add(Query.equal('userId', followingIds));
    }

    // 3. Medya Tipi Filtresi (Reels için)
    if (mediaType != null) {
      queries.add(Query.equal('mediaType', mediaType));
    }

    final res = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.postsCollectionId,
      queries: queries,
    );

    return res.documents.map((d) => Post.fromMap(d.toMap())).toList();
    // 🧠 Çeşitlendirme işlemi artık Provider'da yapılacak
  }

  /// 🔴 REALTIME STREAM
  Stream<List<Post>> getPostsStream() {
    final controller = StreamController<List<Post>>();

    void load() async {
      final res = await _databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.postsCollectionId,
        queries: [
          Query.orderDesc('score'), // 🧠 Yeni Algoritma
          Query.orderDesc('\$createdAt')
        ],
      );

      controller.add(
        res.documents
            .map((d) => Post.fromMap(d.toMap())).toList(),
      );
    }

    load();

    final sub = _realtime.subscribe([
      'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.postsCollectionId}.documents',
    ]);

    sub.stream.listen((_) => load());

    controller.onCancel = () {
      sub.close();
      controller.close();
    };

    return controller.stream;
  }

  /// 🔴 REALTIME: Tek Post Stream (Detay Sayfası İçin)
  Stream<models.Document> getPostStream(String postId) {
    final controller = StreamController<models.Document>();

    void load() async {
      try {
        final doc = await _databases.getDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.postsCollectionId,
          documentId: postId,
        );
        if (!controller.isClosed) controller.add(doc);
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    load();

    final sub = _realtime.subscribe([
      'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.postsCollectionId}.documents.$postId',
    ]);

    sub.stream.listen((event) {
      // Sadece update olaylarında veriyi yenilemek yeterli
      if (event.events.any((e) => e.endsWith('.update'))) {
        // Payload'ı direkt kullanabiliriz ama garanti olsun diye fetch yapıyoruz
        // (Payload bazen eksik attribute içerebilir)
        load(); 
      }
    });

    controller.onCancel = () {
      sub.close();
      controller.close();
    };

    return controller.stream;
  }

  /// 🖼️ GÖRSEL URL (Legacy support - MediaService kullanın)
  String getImageUrl(String fileId) {
    return MediaService.getFileUrl(fileId);
  }

  /// 💬 YORUMLARI GETİR
  Future<List<models.Document>> getComments(String postId) async {
    List<String> queries = [
      Query.equal('postId', postId),
      // 🟢 Index oluşturulduğu için artık popülerlik sıralaması aktif
      Query.orderDesc('likesCount'), 
      Query.orderDesc('\$createdAt'),
    ];

    final res = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.commentsCollectionId,
      queries: queries,
    );
    return res.documents;
  }

  /// 👤 KULLANICININ YORUMLARINI GETİR (Profil/Ayarlar için)
  Future<List<models.Document>> getUserComments(String userId) async {
    final res = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.commentsCollectionId,
      queries: [
        Query.equal('userId', userId),
        Query.orderDesc('\$createdAt'),
      ],
    );
    return res.documents;
  }

  /// 🔴 REALTIME: Yorumlar Stream
  Stream<List<models.Document>> getCommentsStream(String postId) {
    final controller = StreamController<List<models.Document>>();

    void load() async {
      try {
        final res = await _databases.listDocuments(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.commentsCollectionId,
          queries: [
            Query.equal('postId', postId),
            Query.orderDesc('likesCount'), // 🟢 Index var, aktif edildi
            Query.orderDesc('\$createdAt'),
          ],
        );
        if (!controller.isClosed) controller.add(res.documents);
      } catch (e) {
        // Hata yönetimi
      }
    }

    load();

    // Yorumlar koleksiyonunu dinle
    final sub = _realtime.subscribe([
      'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.commentsCollectionId}.documents',
    ]);

    sub.stream.listen((event) {
      // İlgili postun yorumları değiştiyse yenile (basit kontrol)
      // Payload içindeki postId kontrolü yapılabilir ama load() zaten query atıyor.
      final payload = event.payload;
      if (payload['postId'] == postId) {
        load();
      }
    });

    controller.onCancel = () {
      sub.close();
      controller.close();
    };

    return controller.stream;
  }

  /// ✍️ YORUM YAP
  Future<void> createComment(String postId, String userId, String content) async {
    // 1. Yorum Oluştur
    await _databases.createDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.commentsCollectionId,
      documentId: ID.unique(),
      data: {
        'postId': postId,
        'userId': userId,
        'content': content,
        // 'createdAt': ... ❌ Appwrite otomatik ekler
      },
    );

    // 2. Postun yorum sayısını artır (Atomik işlem için backend function önerilir ama client-side çözüm şimdilik bu)
    models.Document? postDoc;
    try {
      postDoc = await _databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.postsCollectionId,
        documentId: postId,
      );
    } catch (e) {
      print('Post bilgisi alinamadi: $e');
    }
      
    if (postDoc != null) {
      final currentComments = postDoc.data['commentsCount'] ?? 0;
      
      try {
      await _databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.postsCollectionId,
        documentId: postId,
        data: {
          'commentsCount': currentComments + 1,
          'lastActiveAt': DateTime.now().toIso8601String(), // 🟢 Etkileşim oldu, yukarı taşı
        },
      );
      } catch(e) {
         print('Post yorum sayisi guncellenemedi (yetki hatasi olabilir): $e');
      }

      // Gönderen kişinin adını al (Hem yorum bildirimi hem de etiketlemeler için)
      String senderName = 'Bir kullanıcı';
      try {
        final senderDoc = await _databases.getDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.usersCollectionId,
          documentId: userId,
        );
        senderName = senderDoc.data['displayName'] ?? senderName;
      } catch (_) {}

      final postOwnerId = postDoc.data['userId'];

      try {
      // 🔔 Bildirim Gönder (Post Sahibine)

      if (postOwnerId != userId) {
        // Appwrite limitlerine takılmamak için yorum içeriğini kısalt
        final displayContent = content.length > 50 ? '${content.substring(0, 50)}...' : content;

        await _databases.createDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.notificationsCollectionId,
          documentId: ID.unique(),
          data: {
            'toUserId': postOwnerId,
            'fromUserId': userId,
            'type': 'comment',
            'eventId': postId,
            'content': '$senderName gönderine yorum yaptı: "$displayContent"',
            'status': 'unread',
            'isRead': false,
          },
        );
      }
      } catch (e) {
        print('Yorum bildirimi olusturulamadi: $e');
      }

      // 🔔 Etiketlenen Kullanıcılara Bildirim Gönder (@username)
      // Regex: @ ile başlayan, harf/rakam/_/./- içeren kelimeler
      final mentionRegex = RegExp(r"@([a-zA-Z0-9_.-]+)"); 
      final matches = mentionRegex.allMatches(content);
      
      if (matches.isNotEmpty) {

        // Tekrar eden bildirimleri önlemek için set kullan
        final Set<String> mentionedUsernames = matches
            .map((m) => m.group(1))
            .where((u) => u != null)
            .cast<String>()
            .toSet();

        for (final username in mentionedUsernames) {
          // Username'den User ID bul
          final userRes = await _databases.listDocuments(
            databaseId: AppwriteConfig.databaseId,
            collectionId: AppwriteConfig.usersCollectionId,
            queries: [Query.equal('username', username), Query.limit(1)],
          );

          if (userRes.documents.isNotEmpty) {
            final targetUserId = userRes.documents.first.data['userId'];
            
            // Kendini etiketlediyse veya post sahibi zaten o ise (yukarıda bildirim gitti) atla
            if (targetUserId != userId && targetUserId != postOwnerId) {
              try {
              await _databases.createDocument(
                databaseId: AppwriteConfig.databaseId,
                collectionId: AppwriteConfig.notificationsCollectionId,
                documentId: ID.unique(),
                data: {
                  'toUserId': targetUserId,
                  'fromUserId': userId,
                  'type': 'mention',
                  'eventId': postId,
                  'content': '$senderName bir yorumda senden bahsetti.',
                  'status': 'unread',
                  'isRead': false,
                },
              );
              } catch (e) {
                 print('Mention bildirim hatasi: $e');
              }
            }
          }
        }
      }
    }
  }

  /// ❤️ YORUM BEĞEN / BEĞENME
  Future<void> toggleCommentLike(String commentId, String userId) async {
    try {
      final comment = await _databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.commentsCollectionId,
        documentId: commentId,
      );

      final likes = List<String>.from(comment.data['likes'] ?? []);
      
      if (likes.contains(userId)) {
        likes.remove(userId);
      } else {
        likes.add(userId);
      }

      await _databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.commentsCollectionId,
        documentId: commentId,
        data: {
          'likes': likes,
          'likesCount': likes.length,
        },
      );
    } catch (e) {
      print('Comment like error: $e');
    }
  }

  /// 📊 ANALYTICS & EVENT TRACKING
  /// Algoritmayı beslemek için kullanıcı etkileşimlerini kaydeder.
  Future<void> logEvent({
    required String userId,
    required String postId,
    required String eventType, // 'impression', 'view', 'completion', 'skip', 'share'
    Map<String, dynamic>? metadata,
  }) async {
    try {
      // Appwrite veritabanına izlenme/geçilme olayını kaydet
      await _databases.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: 'analytics', // 🚨 Appwrite'da 'analytics' adında yeni bir koleksiyon oluşturun
        documentId: ID.unique(),
        data: {
          'userId': userId,
          'postId': postId,
          'eventType': eventType,
          'durationMs': metadata != null && metadata.containsKey('duration_ms') ? metadata['duration_ms'] as int : 0,
          // createdAt alanı Appwrite tarafından otomatik eklenecek
        },
      );
    } catch (e) {
      print('Analytics log hatası: $e'); // Analytics hataları kullanıcı deneyimini bozmamalı
    }
  }

  /// 📄 TEK POST GETİR
  Future<Post> getPost(String postId) async {
    final doc = await _databases.getDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.postsCollectionId,
      documentId: postId,
    );
    return Post.fromMap(doc.toMap());
  }

  /// 🔄 Alias for getPost
  Future<Post> getPostById(String postId) => getPost(postId);

  /// 🏷️ HASHTAG İLE POSTLARI GETİR
  Future<List<Post>> getPostsByTag(String tag) async {
    // Başındaki # işaretini temizle (eğer varsa)
    final cleanTag = tag.replaceAll('#', '');
    
    final res = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.postsCollectionId,
      queries: [
        Query.search('content', cleanTag),
        Query.orderDesc('score'), // 🧠 Yeni Algoritma
        Query.orderDesc('\$createdAt'),
      ],
    );

    // Client-side filtreleme: Sadece "kelime" değil, gerçekten "#kelime" geçenleri al
    return res.documents
        .map((d) => Post.fromMap(d.toMap()))
        .where((p) => p.content.contains('#$cleanTag'))
        .toList();
  }

  /// ♾️ INFINITE FEED & ALGORITHM
  /// [cursor]: Sayfalama için son alınan dokümanın ID'si
  /// [sortType]: 'algorithm' (Etkileşim+Yeni), 'newest' (Sadece Yeni), 'popular' (En çok beğeni)
  /// [limit]: Sayfa başına çekilecek gönderi sayısı
  Future<List<Post>> getFeed({
    required int limit,
    String? cursor,
    String sortType = 'algorithm',
    String? universityId,
    bool useUniversityFilter = true, // true: Kendi Üniversitem, false: Diğerleri
    bool isFollowingOnly = false,
    List<String>? followingIds,
    String? mediaType, // 'video' for Reels, null for Home
  }) async {
    List<String> queries = [
      Query.limit(limit),
    ];
    
    // 📌 SNAPSHOT MANTIĞI İÇİN CURSOR
    // Cursor, bir önceki sayfanın son elemanının ID'sidir.
    // Appwrite bu ID'den sonrasını getirir, böylece araya yeni post girse bile kayma olmaz.
    
    // 🚫 REPOSTLARI GİZLE (Sadece Orijinal İçerikler)
    // Reels akışında veya Ana akışta repost kartlarının tekrar görünmesini istemiyoruz.
    queries.add(Query.isNull('repostUserId'));

    // Sayfalama (Pagination)
    if (cursor != null) {
      queries.add(Query.cursorAfter(cursor));
    }

    // 🧠 ALGORİTMA: Sıralama Mantığı
    if (sortType == 'algorithm') {
      // 🆕 YENİ ALGORİTMA: Backend tarafından hesaplanan HackerNews Decay puanına göre sırala
      queries.add(Query.orderDesc('score'));
      queries.add(Query.orderDesc('\$createdAt'));
    } else if (sortType == 'popular') {
      queries.add(Query.orderDesc('likesCount'));
    } else if (sortType == 'trending') {
      // 🆕 TRENDING / RANKING FORMÜLÜ
      // Backend function tarafından hesaplanan 'score' alanına göre sırala.
      queries.add(Query.isNotNull('score'));
      queries.add(Query.orderDesc('score'));
      queries.add(Query.orderDesc('\$createdAt')); // Eşitlik durumunda yenisi üstte
    } else {
      // Default: En Yeniler
      queries.add(Query.orderDesc('\$createdAt'));
    }

    // Filtreler
    if (universityId != null) {
      if (useUniversityFilter) {
        // 1. Kendi Üniversitem
        queries.add(Query.equal('university', universityId));
      } else {
        // 2. Diğer Üniversiteler
        // (Kendi üniversitem HARİÇ diğerleri)
        queries.add(Query.notEqual('university', universityId));
      }
    }

    if (isFollowingOnly) {
      if (followingIds == null || followingIds.isEmpty) return [];
      queries.add(Query.equal('userId', followingIds));
    }

    if (mediaType != null) {
      queries.add(Query.equal('mediaType', mediaType));
    }

    final res = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.postsCollectionId,
      queries: queries,
    );

    return res.documents.map((d) => Post.fromMap(d.toMap())).toList();
    // 🧠 Çeşitlendirme işlemi artık Provider'da yapılacak
  }

  /// 🧠 FEED DIVERSIFICATION (Akış Çeşitlendirme Algoritması)
  /// Aynı kullanıcının gönderilerini arka arkaya göstermeyi engeller.
  List<Post> diversifyFeed(List<Post> posts) { // 🟢 Public yapıldı
    if (posts.length <= 1) return posts;

    List<Post> diversified = [];
    List<Post> buffer = List.from(posts);

    // İlk postu direkt ekle
    diversified.add(buffer.removeAt(0));

    while (buffer.isNotEmpty) {
      String lastUserId = diversified.last.userId;
      
      // Son eklenen kullanıcıdan FARKLI olan ilk postu bul
      int nextIndex = buffer.indexWhere((p) => p.userId != lastUserId);

      if (nextIndex != -1) {
        // Farklı bir kullanıcı bulundu, sıraya onu al
        diversified.add(buffer.removeAt(nextIndex));
      } else {
        // Kalan tüm postlar AYNI kullanıcıya ait, döngüyü bozmamak için mecburen peş peşe ekle
        diversified.addAll(buffer);
        break;
      }
    }

    return diversified;
  }
}
