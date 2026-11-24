import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appwrite/appwrite.dart';

import '../../../../core/config/appwrite_config.dart';
import '../../../../services/appwrite_service.dart';

final eventJoinStatusProvider =
    FutureProvider.family<String, Map<String, String>>((ref, params) async {
  final databases = AppwriteService.databases;

  final eventId = params['eventId']!;
  final userId = params['userId']!;

  final res = await databases.listDocuments(
    databaseId: AppwriteConfig.databaseId,
    collectionId: AppwriteConfig.eventJoinRequestsCollectionId,
    queries: [
      Query.equal('eventId', eventId),
      Query.equal('userId', userId),
      Query.limit(1),
    ],
  );

  if (res.documents.isEmpty) return 'none';

  return res.documents.first.data['status'] as String;
});
