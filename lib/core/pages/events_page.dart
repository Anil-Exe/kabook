import 'package:flutter/material.dart';

/// Etkinlikler sayfası
class EventsPage extends StatelessWidget {
  const EventsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Etkinlikler'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Yaklaşan Etkinlikler',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  _EventItem(
                    title: 'KaBOOK Topluluk Buluşması',
                    date: '15 Ocak 2024',
                    location: 'İstanbul',
                    description: 'Tüm KaBOOK kullanıcılarını bekliyoruz!',
                  ),
                  _EventItem(
                    title: 'Teknoloji Konferansı',
                    date: '20 Ocak 2024',
                    location: 'Ankara',
                    description: 'Sosyal medya ve teknoloji üzerine konuşmalar.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Geçmiş Etkinlikler',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  _EventItem(
                    title: 'KaBOOK Lansman',
                    date: '1 Ocak 2024',
                    location: 'Online',
                    description: 'KaBOOK uygulamasının resmi lansmanı.',
                    isPast: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventItem extends StatelessWidget {
  final String title;
  final String date;
  final String location;
  final String description;
  final bool isPast;

  const _EventItem({
    required this.title,
    required this.date,
    required this.location,
    required this.description,
    this.isPast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPast
            ? Theme.of(context).colorScheme.surfaceVariant
            : Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 16,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
              const SizedBox(width: 4),
              Text(
                date,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.location_on,
                size: 16,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
              const SizedBox(width: 4),
              Text(
                location,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(description),
          if (!isPast) ...[
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Etkinlik kayıt özelliği yakında eklenecek'),
                  ),
                );
              },
              child: const Text('Katıl'),
            ),
          ],
        ],
      ),
    );
  }
}

