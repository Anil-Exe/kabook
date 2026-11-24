import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'event_service.dart';

/// Kullanıcı bu eventi beğenmiş mi?
final isEventLikedProvider =
    FutureProvider.family<bool, Map<String, String>>((ref, params) async {
  final eventId = params['eventId']!;
  final userId = params['userId']!;

  return ref.read(eventServiceProvider).isEventLiked(eventId, userId);
});

/// Like / Unlike işlemi
final toggleEventLikeProvider =
    FutureProvider.family<void, Map<String, String>>((ref, params) async {
  final eventId = params['eventId']!;
  final userId = params['userId']!;

  await ref.read(eventServiceProvider).toggleLike(eventId, userId);
});
