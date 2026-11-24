import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart'; // Tarih formatı için
import 'package:appwrite/appwrite.dart'; // Query için

import '../../../../core/theme/app_theme.dart';
import '../../data/providers/event_providers.dart';
import '../../data/providers/event_realtime_provider.dart'; // 🔥 DOĞRU
import '../../data/event_model.dart';
import '../../../../core/config/appwrite_config.dart';
import '../../../../services/appwrite_service.dart';
import 'create_event_page.dart';

/// Seçili kategori durumu
final selectedCategoryProvider = StateProvider<String>((ref) => 'Tümü');

class EventsPage extends ConsumerWidget {
  const EventsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 🔥 EVENT REALTIME DİNLEME BURADA BAŞLAR
    ref.watch(eventRealtimeProvider);

    final eventsAsync = ref.watch(eventsProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);

    final categories = ['Tümü', 'Müzik', 'Spor', 'Sanat', 'Eğitim', 'Teknoloji', 'Gezi', 'Yeme-İçme', 'Diğer'];

    // Scaffold ve AppBar kaldırıldı (MainLayout yönetiyor)
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateEventPage()),
          );
        },
        backgroundColor: AppColors.primaryGreen,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(
        children: [
          // 🏷️ KATEGORİ FİLTRESİ
          Container(
            height: 50,
            margin: const EdgeInsets.symmetric(vertical: 10),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final category = categories[index];
                final isSelected = category == selectedCategory;
                return ChoiceChip(
                  label: Text(category),
                  selected: isSelected,
                  showCheckmark: false,
                  onSelected: (selected) {
                    if (selected) {
                      ref.read(selectedCategoryProvider.notifier).state = category;
                    }
                  },
                  selectedColor: AppColors.primaryGreen,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected ? Colors.transparent : Colors.grey.shade300,
                    ),
                  ),
                );
              },
            ),
          ),

          // 📋 ETKİNLİK LİSTESİ
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                return ref.refresh(eventsProvider.future);
              },
              color: AppColors.primaryGreen,
              child: eventsAsync.when(
                data: (events) {
                  final filteredEvents = selectedCategory == 'Tümü'
                      ? events
                      : events.where((e) => e.category == selectedCategory).toList();

                  if (filteredEvents.isEmpty) {
                    return _buildEmptyState();
                  }
                  return ListView.separated(
                    itemCount: filteredEvents.length,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100), // FAB boşluğu
                    separatorBuilder: (context, index) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final event = filteredEvents[index];
                      return _buildEventCard(context, event);
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
                error: (e, _) => Center(child: Text('Hata: $e')),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(BuildContext context, Event event) { // ✅ Tip 'Event' olarak değiştirildi
    final date = event.eventDate;
    final day = date.day.toString();
    final month = DateFormat('MMM', 'tr_TR').format(date).toUpperCase();
    final time = DateFormat('HH:mm').format(date);
    
    // 🖼️ Görsel URL'sini hazırla
    String? imageUrl;
    if (event.imageId != null) {
      imageUrl = '${AppwriteConfig.endpoint}/storage/buckets/${AppwriteConfig.storageBucketId}/files/${event.imageId}/view?project=${AppwriteConfig.projectId}';
    }
    
    return GestureDetector(
      onTap: () => context.push('/event/${event.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.grey.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🖼️ GÖRSEL ALANI (Placeholder)
            Stack(
              children: [
                Container(
                  height: 140,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withOpacity(0.1),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    image: DecorationImage(
                      image: imageUrl != null 
                          ? NetworkImage(imageUrl) 
                          : const AssetImage('assets/images/event_placeholder.png') as ImageProvider,
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: imageUrl == null 
                      ? const Center(child: Icon(Icons.event, size: 48, color: AppColors.primaryGreen))
                      : null,
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      event.category,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 📅 TARİH ROZETİ
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(day, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primaryGreen)),
                        Text(month, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryGreen)),
                        Text(time, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black54)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // 📝 BİLGİLER
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        
                        // 👤 ETKİNLİK SAHİBİ (EKLENDİ)
                        FutureBuilder(
                          future: AppwriteService.databases.getDocument(
                            databaseId: AppwriteConfig.databaseId,
                            collectionId: AppwriteConfig.usersCollectionId,
                            documentId: event.creatorId,
                          ),
                          builder: (context, snapshot) {
                            String creatorName = '';
                            if (snapshot.hasData) {
                              final data = snapshot.data!.data;
                              creatorName = data['displayName'] ?? data['username'] ?? '';
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 2, bottom: 4),
                              child: Text(
                                creatorName.isNotEmpty ? 'Düzenleyen: $creatorName' : '',
                                style: TextStyle(fontSize: 12, color: AppColors.primaryGreen.withOpacity(0.8), fontWeight: FontWeight.w500),
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(child: Text(event.location, style: const TextStyle(color: Colors.grey, fontSize: 13), maxLines: 1)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // Katılımcı Sayısı (Modelde varsa)
                            const Icon(Icons.people_outline, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            // Text('${event.participantsCount ?? 0} Katılımcı', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            Text('${event.participantsCount}/${event.maxParticipants} Katılımcı', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            
                            const Spacer(),
                            
                            // Fiyat (Placeholder)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Ücretsiz',
                                style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('Henüz etkinlik yok.', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
