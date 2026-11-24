import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:appwrite/appwrite.dart';
import '../../../core/theme/app_theme.dart';
import '../data/event_model.dart';
import '../../auth/data/auth_providers.dart';
import '../../../core/config/appwrite_config.dart';
import '../../../services/appwrite_service.dart';

class EventCard extends ConsumerWidget {
  final Event event;

  const EventCard({super.key, required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPast = event.isPast;
    final dateFormat = DateFormat('d MMMM yyyy – HH:mm', 'tr_TR');
    final currentUser = ref.watch(currentUserProvider).value;
    final currentUserId = currentUser?.$id ?? '';
    final isCreator = currentUserId == event.creatorId;

    return Opacity(
      opacity: isPast ? 0.6 : 1.0,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isCreator ? const BorderSide(color: AppColors.brandTeal, width: 1.5) : BorderSide.none,
        ),
        child: InkWell(
          onTap: () => context.push('/event/${event.id}'),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Üst Satır: Tarih ve Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.calendar_today, 
                          size: 16, 
                          color: isPast ? Colors.grey : AppColors.brandTeal
                        ),
                        const SizedBox(width: 6),
                        Text(
                          dateFormat.format(event.eventDate),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isPast ? Colors.grey : AppColors.brandTeal,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        if (isCreator) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.brandTeal.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.brandTeal.withOpacity(0.5)),
                            ),
                            child: const Text(
                              'Senin Etkinliğin',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.brandTeal),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.metallicSurface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.metallicBorder),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.people, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                '${event.participantsCount}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Başlık
                Text(
                  event.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    decoration: isPast ? TextDecoration.lineThrough : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),

                // Konum
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(event.location, style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  ],
                ),

                // Düzenle ve Sil Butonları (Sadece Sahibi İçin)
                if (currentUserId == event.creatorId) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => context.push('/event/${event.id}/edit'),
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Düzenle'),
                        style: TextButton.styleFrom(foregroundColor: AppColors.brandTeal),
                      ),
                      TextButton.icon(
                        onPressed: () => _showDeleteDialog(context, event.id),
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        label: const Text('Sil', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDeleteDialog(BuildContext context, String eventId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Etkinliği Sil'),
        content: const Text('Bu etkinliği silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      try {
        await AppwriteService.databases.deleteDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.eventsCollectionId,
          documentId: eventId,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Etkinlik silindi')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Hata: $e')),
          );
        }
      }
    }
  }
}