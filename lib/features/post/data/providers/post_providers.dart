import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabook_app/core/config/appwrite_config.dart';
import 'package:kabook_app/models/post_model.dart';
import 'package:kabook_app/services/appwrite_service.dart';
import 'package:kabook_app/services/post_service.dart';

/// PostService'i Riverpod ile sağlar
final postServiceProvider = Provider<PostService>((ref) {
  return PostService(AppwriteService.client);
});

/// Tüm gönderileri REALTIME olarak çeker
final postsProvider = StreamProvider<List<Post>>((ref) {
  final postService = ref.watch(postServiceProvider);
  return postService.getPostsStream();
});

/// Tek bir gönderiyi ID ile çeker (isteğe bağlı, ileride kullanabilirsin)
final postProvider = FutureProvider.family<Post, String>((ref, postId) async {
  final postService = ref.read(postServiceProvider);
  return await postService.getPostById(postId);
});

/// Fetches a user's document as a real-time stream.
///
/// This provider is useful when you need to listen for changes to a user's
/// data and have the UI update automatically.
final userDocumentProvider = StreamProvider.family<models.Document, String>((ref, userId) {
  final client = AppwriteService.client;
  final realtime = Realtime(client);

  final subscription = realtime.subscribe([
    'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.usersCollectionId}.documents.$userId'
  ]);

  // Immediately fetch the document to provide an initial value.
  Future<models.Document> fetchInitialDocument() async {
    return AppwriteService.databases.getDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.usersCollectionId,
      documentId: userId,
    );
  }

  // The stream controller will manage the data flow.
  final controller = StreamController<models.Document>();

  // Fetch the initial document and add it to the stream.
  fetchInitialDocument().then((doc) {
    if (!controller.isClosed) {
      controller.add(doc);
    }
  }).catchError((e) {
    if (!controller.isClosed) {
      controller.addError(e);
    }
  });

  // Listen for real-time events.
  subscription.stream.listen((response) async {
    if (response.payload.isNotEmpty && !controller.isClosed) {
      // When an event occurs, refetch the document to get the latest data.
      try {
        final updatedDoc = await fetchInitialDocument();
        controller.add(updatedDoc);
      } catch (e) {
        controller.addError(e);
      }
    }
  });

  // When the provider is disposed, close the stream controller and subscription.
  ref.onDispose(() {
    subscription.close();
    controller.close();
  });

  return controller.stream;
});

/// Fetches all posts created by a specific user.
///
/// This `FutureProvider.family` queries the 'posts' collection for documents
/// where the 'userId' field matches the provided `userId`.
/// It's used to display a list of posts on a user's profile page.
final userPostsProvider = FutureProvider.family<List<Post>, String>((ref, userId) async {
  try {
    final response = await AppwriteService.databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.postsCollectionId,
      queries: [
        Query.equal('userId', userId),
        Query.orderDesc('\$createdAt'),
      ],
    );
    return response.documents
        .map((doc) => Post.fromMap(doc.toMap()))
        .where((p) => !p.isRepost) // 🟢 Sadece orijinal gönderiler
        .toList();
  } on AppwriteException catch (e) {
    print('Failed to get user posts: ${e.message}');
    return [];
  }
});

/// Kullanıcının beğendiği gönderileri getirir
final userLikedPostsProvider = FutureProvider.family<List<Post>, String>((ref, userId) async {
  try {
    final response = await AppwriteService.databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.postsCollectionId,
      queries: [
        Query.equal('likes', userId), // Dizi içinde arama yapar
        Query.orderDesc('\$createdAt'),
      ],
    );
    return response.documents.map((doc) => Post.fromMap(doc.toMap())).toList();
  } on AppwriteException catch (e) {
    print('Failed to get liked posts: ${e.message}');
    return [];
  }
});

/// 📌 Post Detayını Getiren Provider (REALTIME)
final postDetailsProvider = StreamProvider.family<models.Document, String>((ref, postId) {
  final service = ref.watch(postServiceProvider);
  return service.getPostStream(postId);
});

/// 💬 Yorumları Getiren Provider (REALTIME)
final postCommentsProvider = StreamProvider.family<List<models.Document>, String>((ref, postId) {
  final service = ref.watch(postServiceProvider);
  return service.getCommentsStream(postId);
});

/// 👤 Kullanıcının Yaptığı Yorumları Getiren Provider
final userCommentsProvider = FutureProvider.family<List<models.Document>, String>((ref, userId) async {
  final service = ref.read(postServiceProvider);
  return await service.getUserComments(userId);
});

/// Kullanıcının repost ettiği gönderileri getirir
final userRepostsProvider = FutureProvider.family<List<Post>, String>((ref, userId) async {
  try {
    // 1. Önce Repost kayıtlarını çek (userId'nin repostladığı şeyler)
    final response = await AppwriteService.databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.postsCollectionId,
      queries: [
        Query.equal('repostUserId', userId),
        Query.orderDesc('\$createdAt'),
      ],
    );

    // Repost olan Post objelerini döndür. PostCard, orijinal postu kendisi çekecek.
    return response.documents.map((doc) => Post.fromMap(doc.toMap())).toList();
  } on AppwriteException catch (e) {
    print('Failed to get reposts: ${e.message}');
    return [];
  }
});

/// 📊 Kullanıcının Toplam Beğeni Sayısını Hesaplar
final userTotalLikesProvider = FutureProvider.family<int, String>((ref, userId) async {
  final posts = await ref.watch(userPostsProvider(userId).future);
  int total = 0;
  for (var post in posts) {
    total += post.likesCount;
  }
  return total;
});
