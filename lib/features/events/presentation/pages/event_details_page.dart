import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:intl/intl.dart';
import 'package:add_2_calendar/add_2_calendar.dart' as calendar;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../services/appwrite_service.dart';
import '../../../../core/config/appwrite_config.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../profile/data/profile_service.dart';
import '../../data/providers/event_providers.dart';
import '../../data/event_model.dart';
import '../../../../services/event_service.dart';
import '../../data/providers/event_details_realtime_provider.dart';
import '../../data/providers/event_like_realtime_provider.dart';
import '../../../notifications/data/notification_service.dart';

/// 🔥 KAPSAMLI REALTIME PROVIDER
/// Etkinlik, Katılımcılar ve İstekler tablolarını aynı anda dinler.
final eventPageRealtimeProvider = StreamProvider.family<RealtimeMessage, String>((ref, eventId) {
  final realtime = AppwriteService.realtime;
  
  final subscription = realtime.subscribe([
    'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.eventsCollectionId}.documents.$eventId',
    'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.eventParticipantsCollectionId}.documents',
    'databases.${AppwriteConfig.databaseId}.collections.${AppwriteConfig.eventJoinRequestsCollectionId}.documents',
  ]);

  ref.onDispose(() {
    subscription.close();
  });

  return subscription.stream;
});

/// 👥 KATILIMCI LİSTESİ PROVIDER
/// Realtime ile tetiklenip listeyi yenileyecek olan provider
final eventParticipantsListProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, eventId) async {
  final databases = AppwriteService.databases;
  final profileService = ref.read(profileServiceProvider);
  
  try {
    final participantDocs = await databases.listDocuments(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.eventParticipantsCollectionId,
      queries: [
        Query.equal('eventId', eventId),
      ],
    );

    if (participantDocs.documents.isEmpty) return [];

    final userIds = participantDocs.documents
        .map((doc) => doc.data['userId'] as String)
        .toList();

    List<Map<String, dynamic>> users = [];

    for (var uid in userIds) {
      try {
        Map<String, dynamic>? userData = await profileService.getProfile(uid);

        if (userData == null) {
          final userDoc = await databases.getDocument(
            databaseId: AppwriteConfig.databaseId,
            collectionId: AppwriteConfig.usersCollectionId,
            documentId: uid,
          );
          userData = userDoc.data;
        }

        if (userData != null && userData['userId'] == null) {
          userData['userId'] = uid;
        }

        if (userData == null) {
          userData = {
            'userId': uid,
            'displayName': 'Kullanıcı',
            'username': 'unknown',
            'university': 'Bilgi yok',
          };
        }
        users.add(userData);
      } catch (e) {
        debugPrint('Kullanıcı detayı alınamadı: $uid');
      }
    }
    return users;
    
  } catch (e) {
    debugPrint('Katılımcılar yüklenirken hata: $e');
    return [];
  }
});

class EventDetailsPage extends ConsumerWidget {
  final String eventId;
  const EventDetailsPage({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider).value;

    /// ✅ REALTIME → PROVIDER INVALIDATE
    ref.listen(eventPageRealtimeProvider(eventId), (previous, next) {
      if (next.hasValue) {
        final payload = next.value!.payload;
        // Sadece bu etkinlikle ilgili değişikliklerde yenile
        if (payload['eventId'] == eventId || payload['\$id'] == eventId) {
          ref.invalidate(eventDetailsProvider(eventId));
          ref.invalidate(eventParticipantsListProvider(eventId)); // Listeyi yenile
          ref.invalidate(eventJoinRequestsProvider(eventId));
          
          if (currentUser != null) {
            ref.invalidate(userJoinStatusProvider('$eventId|${currentUser.$id}'));
          }
        }
      }
    });

    ref.listen(eventLikeRealtimeProvider(eventId), (_, __) {
      ref.invalidate(eventDetailsProvider(eventId));
    });

    final eventAsync = ref.watch(eventDetailsProvider(eventId));

    return Scaffold(
      appBar: AppBar(title: const Text('Etkinlik Detayı')),
      body: eventAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (event) {
          final isCreator = currentUser?.$id == event.creatorId;
          
          final List<String> images = [];
          if (event.imageId != null) {
            images.add(event.imageId!);
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// ===== IMAGE GALLERY =====
                if (images.isNotEmpty) ...[
                  _EventGallery(images: images),
                  const SizedBox(height: 20),
                ],

                /// ===== CATEGORY CHIP =====
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primaryGreen.withOpacity(0.2)),
                  ),
                  child: Text(
                    event.category,
                    style: const TextStyle(
                      color: AppColors.primaryGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                /// ===== TITLE + LIKE =====
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 5,
                        children: [
                          Text(
                            event.title,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryGreen,
                                ),
                          ),
                          if (isCreator)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.brandTeal.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.brandTeal.withOpacity(0.5)),
                              ),
                              child: const Text(
                                'Senin Etkinliğin',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.brandTeal),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (currentUser != null)
                      _LikeButton(
                        eventId: eventId,
                        userId: currentUser.$id,
                        creatorId: event.creatorId,
                        eventTitle: event.title,
                        userName: currentUser.name,
                      ),
                  ],
                ),

                const SizedBox(height: 20),

                /// ===== DATE & LOCATION & CALENDAR =====
                _EventInfoSection(event: event),

                const SizedBox(height: 20),

                /// ===== DESCRIPTION =====
                if (event.description != null && event.description!.isNotEmpty) ...[
                  Text(
                    "Açıklama",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    event.description!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 20),
                ],

                /// ===== CREATOR ACTIONS (Düzenle / Sil) =====
                if (isCreator) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.push('/event/$eventId/edit'),
                          icon: const Icon(Icons.edit, size: 18),
                          label: const Text('Düzenle'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showDeleteDialog(context, eventId),
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          label: const Text('Sil', style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],

                /// ===== JOIN BUTTON =====
                if (currentUser != null && !isCreator)
                  _JoinRequestButton(
                    eventId: eventId,
                    userId: currentUser.$id,
                    creatorId: event.creatorId,
                    eventTitle: event.title,
                    userName: currentUser.name,
                  ),

                const SizedBox(height: 32),

                /// ===== PARTICIPANTS =====
                Row(
                  children: [
                    const Text(
                      'Katılımcılar',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${event.participantsCount})',
                      style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ParticipantsList(eventId: eventId, isCreator: isCreator),

                /// ===== JOIN REQUESTS (CREATOR) =====
                if (isCreator) ...[
                  const SizedBox(height: 32),
                  const Text(
                    'Katılım İstekleri',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _JoinRequestsList(eventId: eventId),
                ],
              ],
            ),
          );
        },
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
          context.pop(); // Detay sayfasından çık
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

/// ================= INFO SECTION (Date, Location, Calendar) =================
class _EventInfoSection extends StatelessWidget {
  final Event event;
  const _EventInfoSection({required this.event});

  Future<void> _openMap(String location) async {
    final query = Uri.encodeComponent(location);
    final googleMapsUrl = Uri.parse("https://www.google.com/maps/search/?api=1&query=$query");
    if (!await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication)) {
      debugPrint('Harita açılamadı: $googleMapsUrl');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 18, color: AppColors.primaryGreen),
              const SizedBox(width: 8),
              Text(
                DateFormat('d MMMM yyyy', 'tr_TR').format(event.eventDate),
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              const Icon(Icons.access_time, size: 18, color: AppColors.primaryGreen),
              const SizedBox(width: 8),
              Text(
                DateFormat('HH:mm').format(event.eventDate),
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 18, color: AppColors.primaryGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  event.location,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final calendarEvent = calendar.Event(
                      title: event.title,
                      description: event.description,
                      location: event.location,
                      startDate: event.eventDate,
                      endDate: event.eventDate.add(const Duration(hours: 2)),
                      allDay: false,
                    );
                    calendar.Add2Calendar.addEvent2Cal(calendarEvent);
                  },
                  icon: const Icon(Icons.calendar_month, size: 18),
                  label: const Text('Takvime Ekle', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openMap(event.location),
                  icon: const Icon(Icons.map, size: 18),
                  label: const Text('Haritada Aç', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ================= LIKE BUTTON =================
class _LikeButton extends ConsumerWidget {
  final String eventId;
  final String userId;
  final String creatorId;
  final String eventTitle;
  final String userName;

  const _LikeButton({
    required this.eventId,
    required this.userId,
    required this.creatorId,
    required this.eventTitle,
    required this.userName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLikedAsync = ref.watch(
      isEventLikedProvider('$eventId|$userId'),
    );

    return isLikedAsync.when(
      loading: () => const SizedBox(width: 24, height: 24),
      error: (_, __) => const SizedBox.shrink(),
      data: (isLiked) => IconButton(
        icon: Icon(
          isLiked ? Icons.favorite : Icons.favorite_border,
          color: isLiked ? Colors.red : Colors.grey,
        ),
        onPressed: () async {
          await ref
              .read(eventServiceProvider)
              .toggleLike(eventId, userId);

          if (!isLiked) {
            await ref.read(notificationServiceProvider).createNotification(
                  toUserId: creatorId,
                  fromUserId: userId,
                  type: 'event',
                  content: '$userName, "$eventTitle" etkinliğini beğendi',
                  eventId: eventId,
                );
          }

          ref.invalidate(
            isEventLikedProvider('$eventId|$userId'),
          );
        },
      ),
    );
  }
}

/// ================= IMAGE GALLERY =================
class _EventGallery extends StatelessWidget {
  final List<String> images;
  const _EventGallery({required this.images});

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    final cover = images.first;
    final coverUrl = AppwriteService.getFilePreviewUrl(cover).replaceAll('/preview', '/view');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cover Image
        GestureDetector(
          onTap: () => _openFullscreen(context, cover),
          child: Container(
            width: double.infinity,
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.grey[200],
              image: DecorationImage(
                image: NetworkImage(coverUrl),
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        
        // Horizontal Gallery
        if (images.length > 1) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final img = images[index];
                final isCover = img == cover;
                final imgUrl = AppwriteService.getFilePreviewUrl(img).replaceAll('/preview', '/view');
                return GestureDetector(
                  onTap: () => _openFullscreen(context, img),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: isCover 
                          ? Border.all(color: AppColors.brandTeal, width: 2) 
                          : Border.all(color: Colors.transparent),
                      image: DecorationImage(
                        image: NetworkImage(imgUrl),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  void _openFullscreen(BuildContext context, String fileId) {
    // Preview URL'i View URL'e çevir (daha yüksek kalite için)
    final url = AppwriteService.getFilePreviewUrl(fileId).replaceAll('/preview', '/view');
    
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(url),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ================= JOIN REQUEST BUTTON =================
class _JoinRequestButton extends ConsumerStatefulWidget {
  final String eventId;
  final String userId;
  final String creatorId;
  final String eventTitle;
  final String userName;

  const _JoinRequestButton({
    required this.eventId,
    required this.userId,
    required this.creatorId,
    required this.eventTitle,
    required this.userName,
  });

  @override
  ConsumerState<_JoinRequestButton> createState() => _JoinRequestButtonState();
}

class _JoinRequestButtonState extends ConsumerState<_JoinRequestButton> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(
      userJoinStatusProvider('${widget.eventId}|${widget.userId}'),
    );

    return statusAsync.when(
      loading: () => SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: null,
          style: ElevatedButton.styleFrom(
            disabledBackgroundColor: AppColors.primaryGreen.withOpacity(0.5),
            disabledForegroundColor: Colors.white,
          ),
          child: const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (status) {
        String text;
        Color color;
        VoidCallback? onPressed;

        switch (status) {
          case 'pending':
            text = 'İsteği İptal Et';
            color = Colors.orange;
            onPressed = _isLoading ? null : () async {
              setState(() => _isLoading = true);
              try {
                await ref.read(eventServiceProvider).cancelJoinRequest(
                      eventId: widget.eventId,
                      userId: widget.userId,
                    );
                ref.invalidate(userJoinStatusProvider('${widget.eventId}|${widget.userId}'));
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
                }
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            };
            break;
          case 'approved': // Hem istek onaylanmış hem de katılımcı listesinde olabilir
            text = 'Katılıyorsun';
            color = Colors.green;
            break;
          case 'rejected':
            text = 'Reddedildi';
            color = Colors.red;
            break;
          default:
            text = 'Katıl';
            color = AppColors.primaryGreen;
            onPressed = _isLoading ? null : () async {
              setState(() => _isLoading = true);
              try {
                await ref.read(eventServiceProvider).sendJoinRequest(
                      eventId: widget.eventId,
                      userId: widget.userId,
                      creatorId: widget.creatorId,
                    senderName: widget.userName,
                    );

                await ref.read(notificationServiceProvider).createNotification(
                      toUserId: widget.creatorId,
                      fromUserId: widget.userId,
                      type: 'event',
                      content: '${widget.userName}, "${widget.eventTitle}" etkinliğine katılmak istiyor',
                      eventId: widget.eventId,
                    );

                ref.invalidate(
                  userJoinStatusProvider(
                      '${widget.eventId}|${widget.userId}'),
                );
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Hata: $e')),
                  );
                }
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            };
        }

        return SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              disabledBackgroundColor: color.withOpacity(0.7),
              disabledForegroundColor: Colors.white,
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(text),
          ),
        );
      },
    );
  }
}

/// ================= PARTICIPANTS =================
class _ParticipantsList extends ConsumerWidget {
  final String eventId;
  final bool isCreator;
  const _ParticipantsList({required this.eventId, required this.isCreator});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final participantsAsync = ref.watch(eventParticipantsListProvider(eventId));

    return participantsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Text('Katılımcılar yüklenemedi'),
      data: (users) {
        if (users.isEmpty) {
          return const Text('Henüz katılımcı yok.');
        }

        return Column(
          children: users.map((data) {
            final name = data['displayName'] ?? data['username'] ?? 'İsimsiz Kullanıcı';
            final university = data['university'];
            final department = data['department'];
            final photoId = data['profileImageUrl'] ?? data['photoId'];

            String subtitleText = '';
            if (university != null && university.toString().isNotEmpty) {
              subtitleText = university;
            }
            if (department != null && department.toString().isNotEmpty) {
              if (subtitleText.isNotEmpty) {
                subtitleText += ' / $department';
              } else {
                subtitleText = department;
              }
            }

            return ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => context.push('/profile/${data['userId']}'),
              leading: CircleAvatar(
                backgroundColor: AppColors.softGreen,
                backgroundImage: (photoId != null && photoId.isNotEmpty)
                    ? NetworkImage(AppwriteService.getFilePreviewUrl(photoId).replaceAll('/preview', '/view'))
                    : null,
                child: (photoId == null || photoId.isEmpty)
                    ? const Icon(Icons.person, color: Colors.white)
                    : null,
              ),
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: subtitleText.isNotEmpty ? Text(subtitleText, style: const TextStyle(fontSize: 12, color: Colors.grey)) : null,
              trailing: isCreator
                  ? IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Katılımcıyı Çıkar'),
                            content: Text('$name adlı kullanıcıyı etkinlikten çıkarmak istiyor musunuz?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
                              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Çıkar', style: TextStyle(color: Colors.red))),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await ref.read(eventServiceProvider).removeParticipant(eventId: eventId, userId: data['userId']);
                          ref.invalidate(eventDetailsProvider(eventId)); // Listeyi yenile
                        }
                      },
                    )
                  : null,
            );
          }).toList(),
        );
      },
    );
  }
}

/// ================= JOIN REQUESTS (CREATOR) =================
class _JoinRequestsList extends ConsumerWidget {
  final String eventId;
  const _JoinRequestsList({required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(eventJoinRequestsProvider(eventId));

    return requestsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const Text('İstekler yüklenemedi'),
      data: (requests) {
        final pending =
            requests; // Provider zaten sadece pending'leri getiriyor

        if (pending.isEmpty) {
          return const Text('Bekleyen istek yok.');
        }

        return Column(
          children: pending.map((r) {
            return _JoinRequestTile(
              requestId: r['\$id'],
              eventId: eventId,
              userId: r['userId'],
            );
          }).toList(),
        );
      },
    );
  }
}

/// ================= JOIN REQUEST TILE =================
class _JoinRequestTile extends ConsumerWidget {
  final String requestId;
  final String eventId;
  final String userId;

  const _JoinRequestTile({
    required this.requestId,
    required this.eventId,
    required this.userId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userProfileAsync = ref.watch(userProfileProvider(userId));

    return userProfileAsync.when(
      loading: () => const Card(child: ListTile(title: Text('Yükleniyor...'))),
      error: (_, __) => Card(child: ListTile(title: Text('Kullanıcı: $userId'))),
      data: (user) {
        final name = user?['displayName'] ?? user?['username'] ?? 'Kullanıcı';
        final username = user?['username'] ?? userId;
        final photoId = user?['profileImageUrl'] ?? user?['photoId'];

        return Card(
          child: ListTile(
            onTap: () => context.push('/profile/$userId'),
            leading: CircleAvatar(
              backgroundColor: AppColors.softGreen,
              backgroundImage: (photoId != null && photoId.isNotEmpty)
                  ? NetworkImage(AppwriteService.getFilePreviewUrl(photoId).replaceAll('/preview', '/view'))
                  : null,
              child: (photoId == null || photoId.isEmpty)
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
            ),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text('@$username', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  onPressed: () async {
                    await ref.read(eventServiceProvider).approveJoinRequest(
                          requestId: requestId,
                          eventId: eventId,
                          userId: userId,
                        );
                    ref.invalidate(eventJoinRequestsProvider(eventId));
                    ref.invalidate(eventParticipantsProvider(eventId));
                    ref.invalidate(eventDetailsProvider(eventId));
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () async {
                    await ref.read(eventServiceProvider).rejectJoinRequest(
                          requestId: requestId,
                          eventId: eventId,
                          userId: userId,
                        );
                    ref.invalidate(eventJoinRequestsProvider(eventId));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
