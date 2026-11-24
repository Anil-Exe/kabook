import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/settings_providers.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            /// 🔐 ŞİFRE DEĞİŞTİR
            ListTile(
              leading: const Icon(Icons.lock),
              title: const Text('Şifre Değiştir'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _showChangePasswordDialog(context, ref),
            ),

            const Divider(),

            /// 🚪 ÇIKIŞ YAP
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Çıkış Yap',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () async {
                await ref.read(settingsServiceProvider).logout();

                if (context.mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    '/login',
                    (route) => false,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// ================= CHANGE PASSWORD MODAL =================
  void _showChangePasswordDialog(BuildContext context, WidgetRef ref) {
    final oldController = TextEditingController();
    final newController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Şifre Değiştir'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Mevcut Şifre',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Yeni Şifre',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('İptal'),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
            ),
            child: const Text('Kaydet'),
            onPressed: () async {
              await ref.read(settingsServiceProvider).changePassword(
                    oldPassword: oldController.text,
                    newPassword: newController.text,
                  );

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Şifre başarıyla değiştirildi'),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
