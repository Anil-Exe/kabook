import 'package:appwrite/appwrite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/appwrite_config.dart';
import '../../../../services/appwrite_service.dart';
import '../event_model.dart';
import '../../../../services/event_service.dart';

/// 📋 Tüm etkinlikler
final eventsProvider = FutureProvider<List<Event>>((ref) async {
  final databases = AppwriteService.databases;

  final result = await databases.listDocuments(
    databaseId: AppwriteConfig.databaseId,
    collectionId: AppwriteConfig.eventsCollectionId,
    queries: [Query.orderDesc('\$createdAt')],
  );

  return result.documents.map(Event.fromDocument).toList();
});

/// 📌 Etkinlik detayı
final eventDetailsProvider =
    FutureProvider.family<Event, String>((ref, eventId) async {
  final databases = AppwriteService.databases;

  final doc = await databases.getDocument(
    databaseId: AppwriteConfig.databaseId,
    collectionId: AppwriteConfig.eventsCollectionId,
    documentId: eventId,
  );

  return Event.fromDocument(doc);
});

/// 👥 Katılımcılar
final eventParticipantsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, eventId) async {
  final databases = AppwriteService.databases;

  final res = await databases.listDocuments(
    databaseId: AppwriteConfig.databaseId,
    collectionId: AppwriteConfig.eventParticipantsCollectionId,
    queries: [Query.equal('eventId', eventId)],
  );

  return res.documents.map((d) => d.data).toList();
});

/// ❤️ Like durumu
final isEventLikedProvider =
    FutureProvider.family<bool, String>((ref, compositeKey) {
  final params = compositeKey.split('|');
  return ref
      .read(eventServiceProvider)
      .isEventLiked(params[0], params[1]);
});

/// 👤 Join status
final userJoinStatusProvider =
    FutureProvider.family<String?, String>((ref, compositeKey) {
  final parts = compositeKey.split('|');
  return ref
      .read(eventServiceProvider)
      .getUserJoinStatus(parts[0], parts[1]);
});

/// 📩 Join requests (creator)
final eventJoinRequestsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, eventId) async {
  final docs = await ref.read(eventServiceProvider).getPendingRequests(eventId);
  return docs.map((d) => d.data).toList();
});
