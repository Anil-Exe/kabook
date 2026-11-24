import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/data/auth_providers.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authService = ref.watch(authServiceProvider);
    
    // Tema durumunu kontrol et (Şimdilik sistem teması)
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          
          // 👤 HESAP
          _SectionHeader(title: 'Hesap'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Profili Düzenle'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => context.push('/edit-profile'),
          ),
          
          const Divider(),

          // 🎨 GÖRÜNÜM
          _SectionHeader(title: 'Görünüm'),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('Koyu Tema'),
            subtitle: const Text('Cihaz temasını kullanır'),
            value: isDark,
            onChanged: (val) {
              // Tema değiştirme mantığı henüz eklenmediği için
              // kullanıcıya bilgi veriyoruz.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tema şu an cihaz ayarlarına göre belirlenmektedir.')),
              );
            },
          ),

          const Divider(),

          // ℹ️ HAKKINDA
          _SectionHeader(title: 'Hakkında'),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Yardım'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => context.push('/help'),
          ),
          
          const SizedBox(height: 32),

          // 🚪 ÇIKIŞ
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              onPressed: () async {
                await authService.logout();
                if (context.mounted) {
                  context.go('/login');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.logout),
              label: const Text('Çıkış Yap'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).primaryColor,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}