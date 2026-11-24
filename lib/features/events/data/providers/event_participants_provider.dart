import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appwrite/appwrite.dart';

import '../../../../core/config/appwrite_config.dart';
import '../../../../services/appwrite_service.dart';

final eventParticipantsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, eventId) async {
  final db = AppwriteService.databases;

  final res = await db.listDocuments(
    databaseId: AppwriteConfig.databaseId,
    collectionId: AppwriteConfig.eventParticipantsCollectionId,
    queries: [
      Query.equal('eventId', eventId),
      Query.equal('status', 'approved'),
    ],
  );

  return res.documents.map((d) {
    final data = d.data;
    data['\$id'] = d.$id;
    return data;
  }).toList();
});
