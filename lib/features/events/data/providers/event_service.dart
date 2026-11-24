import 'package:appwrite/appwrite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/appwrite_config.dart';
import '../../../../services/appwrite_service.dart';
import '../event_model.dart';

final eventServiceProvider = Provider<EventService>((ref) {
  return EventService(ref);
});

class EventService {
  final Ref ref;
  final Databases _databases = AppwriteService.databases;

  EventService(this.ref);

  // ================= EVENT =================

  Future<void> createEvent(Event event) async {
    final data = event.toMap();
    data.remove('\$createdAt');

    await _databases.createDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.eventsCollectionId,
      documentId: ID.unique(),
      data: data,
      permissions: [
        Permission.read(Role.any()),
        Permission.update(Role.user(event.creatorId)),
        Permission.delete(Role.user(event.creatorId)),
      ],
    );
  }

  // ================= LIKES =================

  Future<void> toggleLike(String eventId, String userId) async {
    final docId = '$eventId-$userId';

    try {
      await _databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventLikesCollectionId,
        documentId: docId,
      );

      await _databases.deleteDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventLikesCollectionId,
        documentId: docId,
      );
    } catch (_) {
      await _databases.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventLikesCollectionId,
        documentId: docId,
        data: {
          'eventId': eventId,
          'userId': userId,
        },
      );

      // 🔔 Bildirim Gönder (Beğeni)
      try {
        final eventDoc = await _databases.getDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.eventsCollectionId,
          documentId: eventId,
        );
        if (eventDoc.data['creatorId'] != userId) {
          await _createNotification(
            toUserId: eventDoc.data['creatorId'],
            fromUserId: userId,
            eventId: eventId,
            type: 'event',
            content: 'Bir kullanıcı etkinliğini beğendi.',
          );
        }
      } catch (e) {
        print('Event like bildirim hatası: $e');
      }
    }
  }

  Future<bool> isEventLiked(String eventId, String userId) async {
    try {
      await _databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventLikesCollectionId,
        documentId: '$eventId-$userId',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // ================= JOIN REQUEST =================

  Future<void> sendJoinRequest({
    required String eventId,
    required String userId,
    required String creatorId,
  }) async {
    final existing = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.eventJoinRequestsCollectionId,
      queries: [
        Query.equal('eventId', eventId),
        Query.equal('userId', userId),
        Query.notEqual('status', 'rejected'),
      ],
    );

    if (existing.documents.isNotEmpty) {
      return; // tekrar istek atmasını engeller
    }

    await _databases.createDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.eventJoinRequestsCollectionId,
      documentId: ID.unique(),
      data: {
        'eventId': eventId,
        'userId': userId,
        'creatorId': creatorId,
        'status': 'pending',
      },
      permissions: [
        Permission.read(Role.user(creatorId)),
        Permission.update(Role.user(creatorId)),
      ],
    );

    await _createNotification(
      toUserId: creatorId,
      fromUserId: userId,
      eventId: eventId,
      type: 'event_join_request',
      content: 'Etkinliğine katılmak isteyen biri var!',
    );
  }

  /// 👤 Kullanıcının katılım durumu
  Future<String?> getUserJoinStatus(String eventId, String userId) async {
    final res = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.eventJoinRequestsCollectionId,
      queries: [
        Query.equal('eventId', eventId),
        Query.equal('userId', userId),
      ],
    );

    if (res.documents.isEmpty) return null;
    return res.documents.first.data['status'] as String?;
  }

  /// 📩 Katılım istekleri
  Future<List<Map<String, dynamic>>> getJoinRequests(String eventId) async {
    final res = await _databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.eventJoinRequestsCollectionId,
      queries: [Query.equal('eventId', eventId)],
    );

    return res.documents.map((doc) {
      final data = Map<String, dynamic>.from(doc.data);
      data['\$id'] = doc.$id;
      return data;
    }).toList();
  }

  Future<void> approveJoinRequest({
    required String requestId,
    required String eventId,
    required String userId,
  }) async {
    // request status
    await _databases.updateDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.eventJoinRequestsCollectionId,
      documentId: requestId,
      data: {'status': 'approved'},
    );

    // participant
    await _databases.createDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.eventParticipantsCollectionId,
      documentId: ID.unique(),
      data: {
        'eventId': eventId,
        'userId': userId,
        'joinedAt': DateTime.now().toIso8601String(),
      },
    );

    // participantsCount +
    final eventDoc = await _databases.getDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.eventsCollectionId,
      documentId: eventId,
    );

    final count = (eventDoc.data['participantsCount'] ?? 0) as int;

    await _databases.updateDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.eventsCollectionId,
      documentId: eventId,
      data: {'participantsCount': count + 1},
    );

    await _createNotification(
      toUserId: userId,
      fromUserId: eventDoc.data['creatorId'],
      eventId: eventId,
      type: 'event_join_approved',
      content: 'Etkinlik katılım isteğin onaylandı! 🎉',
    );
  }

  Future<void> rejectJoinRequest(String requestId) async {
    // Önce dokümanı al (userId ve eventId için)
    final requestDoc = await _databases.getDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.eventJoinRequestsCollectionId,
      documentId: requestId,
    );

    await _databases.updateDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.eventJoinRequestsCollectionId,
      documentId: requestId,
      data: {'status': 'rejected'},
    );

    await _createNotification(
      toUserId: requestDoc.data['userId'],
      fromUserId: requestDoc.data['creatorId'] ?? 'system',
      eventId: requestDoc.data['eventId'],
      type: 'event_join_rejected',
      content: 'Etkinlik katılım isteğin maalesef reddedildi.',
    );
  }

  // ================= NOTIFICATION =================

  Future<void> _createNotification({
    required String toUserId,
    required String fromUserId,
    required String eventId,
    required String type,
    required String content,
  }) async {
    await _databases.createDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.notificationsCollectionId,
      documentId: ID.unique(),
      data: {
        'toUserId': toUserId,
        'fromUserId': fromUserId,
        'eventId': eventId,
        'type': type,
        'content': content,
        'status': 'unread',
        'isRead': false,
      },
      permissions: [
        Permission.read(Role.user(toUserId)),
        Permission.update(Role.user(toUserId)),
      ],
    );
  }
}
