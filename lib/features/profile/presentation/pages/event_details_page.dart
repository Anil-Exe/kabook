import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:appwrite/appwrite.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/config/appwrite_config.dart';
import '../../../../services/appwrite_service.dart';
import '../../../events/data/event_model.dart';

// Sayfaya özel provider: ID'ye göre etkinlik detayını çeker
final eventDetailsProvider = FutureProvider.family<Event, String>((ref, eventId) async {
  final databases = AppwriteService.databases;
  try {
    final doc = await databases.getDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.eventsCollectionId,
      documentId: eventId,
    );
    return Event.fromMap(doc.toMap());
  } catch (e) {
    throw Exception('Etkinlik yüklenemedi: $e');
  }
});

class EventDetailsPage extends ConsumerWidget {
  final String eventId;

  const EventDetailsPage({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventDetailsProvider(eventId));
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: eventAsync.when(
        data: (event) => CustomScrollView(
          slivers: [
            // 🖼️ GÖRSEL & APPBAR
            SliverAppBar(
              expandedHeight: 280,
              pinned: true,
              backgroundColor: theme.scaffoldBackgroundColor,
              leading: Container(
                margin: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => context.pop(),
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Placeholder Görsel
                    Container(
                      color: AppColors.primaryGreen.withOpacity(0.2),
                      child: const Center(
                        child: Icon(Icons.event, size: 80, color: AppColors.primaryGreen),
                      ),
                    ),
                    // Varsa gerçek görsel (Backend desteği gelince)
                    // Image.network(imageUrl, fit: BoxFit.cover),
                    
                    // Gradient Overlay (Yazı okunurluğu için)
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                          stops: [0.6, 1.0],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 📝 İÇERİK
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Başlık
                    Text(
                      event.title,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Tarih & Konum Kartı
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.withOpacity(0.1)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            _InfoItem(
                              icon: Icons.calendar_today,
                              title: DateFormat('d MMM yyyy', 'tr_TR').format(event.eventDate),
                              subtitle: DateFormat('HH:mm').format(event.eventDate),
                              color: AppColors.primaryGreen,
                            ),
                            VerticalDivider(color: Colors.grey.withOpacity(0.2), thickness: 1, width: 32),
                            _InfoItem(
                              icon: Icons.location_on,
                              title: event.location,
                              subtitle: 'Konum',
                              color: Colors.orange,
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),

                    // Açıklama
                    Text(
                      'Etkinlik Hakkında',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      event.description,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: isDark ? Colors.grey[300] : Colors.grey[700],
                        height: 1.6,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Düzenleyen (Dummy)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.withOpacity(0.1)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppColors.primaryGreen.withOpacity(0.1),
                            child: const Icon(Icons.person, color: AppColors.primaryGreen),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Düzenleyen', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              Text(
                                'Topluluk / Kulüp', // İleride user verisi çekilebilir
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 100), // Buton için boşluk
                  ],
                ),
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
        error: (e, _) => Center(child: Text('Hata: $e')),
      ),
      
      // 🎟️ KATIL BUTONU
      bottomNavigationBar: eventAsync.hasValue
          ? Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                child: ElevatedButton(
                  onPressed: () {
                    // TODO: Katılma mantığı
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Katılma isteği gönderildi!')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Etkinliğe Katıl',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _InfoItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}