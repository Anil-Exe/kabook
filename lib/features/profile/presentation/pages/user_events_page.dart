import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/appwrite_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../services/appwrite_service.dart';

/// Kullanıcının katıldığı etkinlikleri getiren provider
final userJoinedEventsProvider = FutureProvider.family<List<Document>, String>((ref, userId) async {
  final databases = AppwriteService.databases;
  
  // 1. Kullanıcının katıldığı kayıtları (participants) çek
  final participantsRes = await databases.listDocuments(
    databaseId: AppwriteConfig.databaseId,
    collectionId: AppwriteConfig.eventParticipantsCollectionId,
    queries: [
      Query.equal('userId', userId),
      Query.orderDesc('\$createdAt'),
    ],
  );

  if (participantsRes.documents.isEmpty) return [];

  // 2. Benzersiz Etkinlik ID'lerini al
  final eventIds = participantsRes.documents
      .map((doc) => doc.data['eventId'] as String)
      .toSet()
      .toList();

  if (eventIds.isEmpty) return [];

  // 3. Etkinlik detaylarını çek (Paralel istek)
  final futures = eventIds.map((id) => databases.getDocument(
    databaseId: AppwriteConfig.databaseId,
    collectionId: AppwriteConfig.eventsCollectionId,
    documentId: id,
  ).then((doc) => doc).catchError((_) => null)); // Silinmişse null döner

  final results = await Future.wait(futures);
  
  // Null olanları filtrele ve listeyi döndür
  return results.whereType<Document>().toList();
});

/// Kullanıcının OLUŞTURDUĞU etkinlikleri getiren provider
final userCreatedEventsProvider = FutureProvider.family<List<Document>, String>((ref, userId) async {
  final databases = AppwriteService.databases;

  final res = await databases.listDocuments(
    databaseId: AppwriteConfig.databaseId,
    collectionId: AppwriteConfig.eventsCollectionId,
    queries: [
      Query.equal('creatorId', userId), // Etkinliği oluşturan kişi
      Query.orderDesc('\$createdAt'),
    ],
  );

  return res.documents;
});

class UserEventsPage extends ConsumerWidget {
  final String userId;
  final String viewType; // 'joined' veya 'created'

  const UserEventsPage({super.key, required this.userId, this.viewType = 'joined'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = viewType == 'created' 
        ? ref.watch(userCreatedEventsProvider(userId))
        : ref.watch(userJoinedEventsProvider(userId));

    return Scaffold(
      appBar: AppBar(
        title: Text(viewType == 'created' ? 'Oluşturduğum Etkinlikler' : 'Katıldığım Etkinlikler'),
      ),
      body: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (events) {
          if (events.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.event_busy, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(viewType == 'created' ? 'Henüz etkinlik oluşturmadınız.' : 'Henüz katıldığınız bir etkinlik yok.', 
                      style: const TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index];
              final data = event.data;
              final title = data['title'] ?? 'Başlıksız Etkinlik';
              final dateStr = data['eventDate'];
              final location = data['location'] ?? 'Konum yok';
              final imageId = data['imageId'];
              final DateTime? date = dateStr != null ? DateTime.tryParse(dateStr) : null;

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.brandGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      image: imageId != null
                          ? DecorationImage(
                              image: CachedNetworkImageProvider(AppwriteService.getFilePreviewUrl(imageId)),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: imageId == null
                        ? const Center(child: Icon(Icons.event, color: AppColors.brandGreen))
                        : null,
                  ),
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      if (date != null)
                        Text(
                          '${DateFormat('d MMM yyyy HH:mm', 'tr_TR').format(date)} • $location',
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                    ],
                  ),
                  onTap: () {
                    context.push('/event/${event.$id}');
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}