import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/data/auth_providers.dart';
import '../theme/app_theme.dart';

/// QR Kod sayfası
class QRPage extends ConsumerWidget {
  const QRPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final theme = Theme.of(context);

    // Dummy Data: Anlaşmalı Kafeler
    final cafes = [
      {'name': 'Book & Coffee', 'discount': '%15', 'dist': '200m'},
      {'name': 'Study Station', 'discount': '%10', 'dist': '500m'},
      {'name': 'Kampüs Kafe', 'discount': '%20', 'dist': '1.2km'},
      {'name': 'Library Lounge', 'discount': '%12', 'dist': '800m'},
      {'name': 'Espresso Lab', 'discount': '%15', 'dist': '1.5km'},
    ];

    // Scaffold ve AppBar yok, MainLayout yönetiyor
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 🔹 QR KOD KARTI
          currentUser.when(
            data: (user) {
              if (user == null) return const Text('Giriş yapmanız gerekiyor');
              return _buildQRCard(context, user.$id);
            },
            loading: () => const CircularProgressIndicator(),
            error: (_, __) => const Text('Hata'),
          ),

          const SizedBox(height: 32),

          // 🔹 BAŞLIK
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Anlaşmalı Kafeler',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 🔹 LİSTE
          ...cafes.map((cafe) => _buildCafeCard(context, cafe)),
          
          // Alt barın altında kalmaması için boşluk
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildQRCard(BuildContext context, String userId) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.qr_code_2, size: 200, color: Theme.of(context).colorScheme.onSurface),
          const SizedBox(height: 16),
          Text(
            'Kasiyere gösterin',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildCafeCard(BuildContext context, Map<String, String> cafe) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.store, color: AppColors.primaryGreen),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cafe['name']!,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  '${cafe['dist']} uzakta',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              cafe['discount']!,
              style: const TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
