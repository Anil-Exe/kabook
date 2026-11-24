import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/event_service.dart';

/// Tüm etkinlikleri getirir
final eventsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.read(eventServiceProvider).getEvents();
});

/// Tek bir etkinliğin detaylarını getirir
final eventDetailsProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, eventId) async {
  return ref.read(eventServiceProvider).getEvent(eventId);
});

/// Etkinliğin katılımcılarını getirir
final eventParticipantsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, eventId) async {
  return ref.read(eventServiceProvider).getParticipants(eventId);
});

/// Kullanıcının etkinliğe katılıp katılmadığını kontrol eder
final isUserJoinedProvider = FutureProvider.family<bool, Map<String, String>>((ref, params) async {
  final eventId = params['eventId']!;
  final userId = params['userId']!;
  return ref.read(eventServiceProvider).isUserJoined(eventId, userId);
});