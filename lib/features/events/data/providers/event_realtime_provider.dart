import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/appwrite_config.dart';
import '../../../../services/appwrite_service.dart';
import 'event_providers.dart';

final eventRealtimeProvider =
    Provider.autoDispose<StreamSubscription>((ref) {
  final Realtime realtime = AppwriteService.realtime;

  final subscription = realtime.subscribe([
    'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.eventsCollectionId}.documents'
  ]);

  final streamSub = subscription.stream.listen((_) {
    // 🔥 EVENT LİSTESİ ANINDA YENİLENSİN
    ref.invalidate(eventsProvider);
  });

  ref.onDispose(() {
    streamSub.cancel();
    subscription.close();
  });

  return streamSub;
});
