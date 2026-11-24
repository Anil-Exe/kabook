// lib/models/post_model.dart

class Post {
  final String id;
  final String userId;
  final String content;

  // Medya
  final String? imageId;
  final String? imageUrl;
  
  // 🆕 Çoklu Medya ve Video Desteği
  final List<String> mediaIds; // Birden fazla resim/video ID'si
  final String mediaType; // 'image', 'video', 'text'

  /// ❤️ Like atan kullanıcıların ID listesi
  final List<String> likes;

  final int likesCount;
  final int commentsCount;
  final int sharesCount;
  final int repostsCount;
  final List<String> tags;
  
  // 🆕 Algoritma Alanları
  final int score;
  final DateTime? lastActiveAt;

  /// ⏱ Appwrite otomatik alan
  final DateTime createdAt;
  final DateTime updatedAt;

  // 🔁 Repost bilgileri
  final String? originalPostId;
  final String? repostUserId;
  final DateTime? repostedAt;

  // 🎓 Üniversite bilgisi
  final String? university;

  // 🧠 Client-side alanlar (DB'de YOK)
  final bool isDeleted;
  final DateTime? editedAt;

  Post({
    required this.id,
    required this.userId,
    required this.content,
    this.imageId,
    this.imageUrl,
    this.mediaIds = const [],
    this.mediaType = 'image',
    this.likes = const [],
    this.likesCount = 0,
    this.commentsCount = 0,
    this.sharesCount = 0,
    this.repostsCount = 0,
    this.tags = const [],
    this.score = 0,
    this.lastActiveAt,
    required this.createdAt,
    required this.updatedAt,
    this.originalPostId,
    this.repostUserId,
    this.repostedAt,
    this.university,
    this.isDeleted = false,
    this.editedAt,
  });

  /// 🔹 Appwrite Document → Post
  factory Post.fromMap(Map<String, dynamic> map) {
    final data = map['data'] != null && map['data'] is Map
        ? map['data'] as Map<String, dynamic>
        : map;

    return Post(
      id: map['\$id'] ?? '',
      userId: data['userId'] ?? '',
      content: data['content'] ?? '',

      imageId: data['imageId'],
      imageUrl: data['imageUrl'],

      // mediaIds yoksa imageId'yi listeye ekle (DB uyumluluğu)
      mediaIds: data['mediaIds'] != null 
          ? List<String>.from(data['mediaIds'])
          : (data['imageId'] != null ? [data['imageId']] : []),
      mediaType: data['mediaType'] ?? 'image',

      likes: List<String>.from(data['likes'] ?? []),
      likesCount: (data['likesCount'] as num?)?.toInt() ?? 0,
      commentsCount: (data['commentsCount'] as num?)?.toInt() ?? 0,
      sharesCount: (data['sharesCount'] as num?)?.toInt() ?? 0,
      repostsCount: (data['repostsCount'] as num?)?.toInt() ?? 0,
      tags: List<String>.from(data['tags'] ?? []),
      
      score: (data['score'] as num?)?.toInt() ?? 0,
      lastActiveAt: data['lastActiveAt'] != null ? DateTime.parse(data['lastActiveAt']) : null,

      originalPostId: data['originalPostId'],
      repostUserId: data['repostUserId'],
      repostedAt: data['repostedAt'] != null
          ? DateTime.parse(data['repostedAt'])
          : null,
      
      university: data['university'],

      createdAt: DateTime.parse(map['\$createdAt']),
      updatedAt: DateTime.parse(map['\$updatedAt']),

      isDeleted: false,
      editedAt: null,
    );
  }

  /// 🔹 Flutter → Appwrite (CREATE / UPDATE)
  /// ❗ createdAt / updatedAt GÖNDERİLMEZ
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'content': content,
      'imageId': imageId,
      // 'imageUrl': imageUrl, ❌ URL DB'ye GİTMEZ
      'mediaIds': mediaIds,
      'mediaType': mediaType,
      'likes': likes,
      'likesCount': likesCount,
      'commentsCount': commentsCount,
      'sharesCount': sharesCount,
      'repostsCount': repostsCount,
      // 'tags': tags, ❌ DB ŞEMASINDA YOKSA GÖNDERİLMEZ
      'score': score,
      'lastActiveAt': lastActiveAt?.toIso8601String(),
      'originalPostId': originalPostId,
      'repostUserId': repostUserId,
      'repostedAt': repostedAt?.toIso8601String(),
      'university': university,
      // ❗ createdAt ve updatedAt BURADAN SİLİNDİ.
      // Appwrite bu alanları otomatik yönetir ($createdAt).
    };
  }

  /// 🔁 Repost mu?
  bool get isRepost => originalPostId != null;

  /// 🆕 Soft update için
  Post copyWith({
    String? content,
    bool? isDeleted,
    DateTime? editedAt,
    List<String>? mediaIds,
    String? mediaType,
    String? university,
    int? score,
    DateTime? lastActiveAt,
  }) {
    return Post(
      id: id,
      userId: userId,
      content: content ?? this.content,
      imageId: imageId,
      imageUrl: imageUrl,
      mediaIds: mediaIds ?? this.mediaIds,
      mediaType: mediaType ?? this.mediaType,
      likes: likes,
      likesCount: likesCount,
      commentsCount: commentsCount,
      sharesCount: sharesCount,
      repostsCount: repostsCount,
      tags: tags,
      score: score ?? this.score,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      originalPostId: originalPostId,
      repostUserId: repostUserId,
      repostedAt: repostedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      university: university ?? this.university,
      editedAt: editedAt ?? this.editedAt,
    );
  }
}
