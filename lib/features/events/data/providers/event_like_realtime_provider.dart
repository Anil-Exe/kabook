import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appwrite/appwrite.dart';

import '../../../../services/appwrite_service.dart';
import '../../../../core/config/appwrite_config.dart';
import 'event_providers.dart';

/// 🔥 EVENT LIKE REALTIME
final eventLikeRealtimeProvider =
    Provider.family<RealtimeSubscription, String>((ref, eventId) {
  final realtime = AppwriteService.realtime;

  final subscription = realtime.subscribe([
    // Like koleksiyonu
    'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.eventLikesCollectionId}.documents',
    // Event dokümanı (likesCount için)
    'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.eventsCollectionId}.documents.$eventId',
  ]);

  subscription.stream.listen((_) {
    // 🔄 LIKE değişti → event detayını yenile
    ref.invalidate(eventDetailsProvider(eventId));
  });

  ref.onDispose(() {
    subscription.close();
  });

  return subscription;
});
