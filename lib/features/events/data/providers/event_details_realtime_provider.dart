import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/appwrite_config.dart';
import '../../../../services/appwrite_service.dart';
import 'event_providers.dart';

/// 🔥 Tekil event realtime (AUTO DISPOSE)
final eventDetailsRealtimeProvider =
    Provider.autoDispose.family<StreamSubscription, String>(
        (ref, eventId) {
  final Realtime realtime = AppwriteService.realtime;

  final subscription = realtime.subscribe([
    'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.eventsCollectionId}.documents.$eventId',
    'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.eventParticipantsCollectionId}.documents',
    'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.eventJoinRequestsCollectionId}.documents',
  ]);

  final streamSub = subscription.stream.listen((_) {
    ref.invalidate(eventDetailsProvider(eventId));
    ref.invalidate(eventParticipantsProvider(eventId));
    ref.invalidate(eventJoinRequestsProvider(eventId));
  });

  ref.onDispose(() {
    streamSub.cancel();
    subscription.close();
  });

  return streamSub;
});
