import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../services/image_upload_service.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/data/auth_providers.dart';
import '../../data/theme_provider.dart'; // ThemeProvider import
import '../../../post/presentation/pages/liked_posts_page.dart';
import '../../../post/presentation/pages/my_comments_page.dart';
import '../../../block/presentation/pages/blocked_users_page.dart';


class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(currentUserProvider);
    final userProfileAsync = ref.watch(currentUserProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
      ),
      body: authAsync.when(
        data: (user) {
          if (user == null) {
            return const Center(child: Text('Oturum bulunamadı'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              /// 👤 USER INFO
              Material(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => context.push('/edit-profile'),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        userProfileAsync.when(
                          data: (profile) {
                            final photoId = profile?['photoId'];
                            return CircleAvatar(
                              radius: 28,
                              backgroundImage: photoId != null
                                  ? CachedNetworkImageProvider(
                                      MediaService.getFileUrl(photoId))
                                  : null,
                              child: photoId == null ? const Icon(Icons.person) : null,
                            );
                          },
                          loading: () => const CircleAvatar(radius: 28, child: CircularProgressIndicator()),
                          error: (_, __) => const CircleAvatar(radius: 28, child: Icon(Icons.person)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.email,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Profili Düzenle',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              _buildSectionHeader(context, 'HESAP'),

              /// ✏️ PROFİLİ DÜZENLE
              _SettingsTile(
                icon: Icons.edit,
                title: 'Profili Düzenle',
                onTap: () {
                  context.push('/edit-profile');
                },
              ),
              const SizedBox(height: 8),

              /// 🔐 CHANGE PASSWORD
              _SettingsTile(
                icon: Icons.lock,
                title: 'Şifre Değiştir',
                onTap: () {
                  _showChangePasswordDialog(context, ref);
                },
              ),

              const SizedBox(height: 24),

              _buildSectionHeader(context, 'ETKİLEŞİMLER'),

              /// ❤️ BEĞENDİKLERİM
              _SettingsTile(
                icon: Icons.favorite,
                title: 'Beğendiklerim',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LikedPostsPage()),
                  );
                },
              ),
              const SizedBox(height: 8),

              /// 💬 YORUMLARIM
              _SettingsTile(
                icon: Icons.comment,
                title: 'Yorumlarım',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MyCommentsPage()),
                  );
                },
              ),

              const SizedBox(height: 24),

              _buildSectionHeader(context, 'GİZLİLİK'),

              /// 🔒 GİZLİ HESAP
              userProfileAsync.when(
                data: (profile) {
                  final isPrivate = profile?['isPrivate'] ?? false;
                  return _SettingsTile(
                    icon: isPrivate ? Icons.lock : Icons.lock_open,
                    title: 'Gizli Hesap',
                    trailing: Switch(
                      value: isPrivate,
                      onChanged: (val) async {
                        final user = authAsync.value;
                        if (user != null) {
                          await ref.read(authServiceProvider).updatePrivacy(user.$id, val);
                          // UI'ı güncellemek için profili yenile
                          ref.invalidate(userProvider(user.$id));
                          ref.invalidate(currentUserProfileProvider);
                        }
                      },
                      activeColor: AppColors.primaryGreen,
                    ),
                    onTap: () {}, // Switch zaten işlevi görüyor
                  );
                },
                loading: () => const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator())),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 8),

              /// 🚫 ENGELLENENLER
              _SettingsTile(
                icon: Icons.block,
                title: 'Engellenenler',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => BlockedUsersPage()),
                  );
                },
              ),

              const SizedBox(height: 24),
              _buildSectionHeader(context, 'GÖRÜNÜM'),

              /// 🎨 TEMA DEĞİŞTİR
              Consumer(
                builder: (context, ref, child) {
                  final themeMode = ref.watch(themeModeProvider);
                  final isDark = themeMode == ThemeMode.dark;
                  
                  return _SettingsTile(
                    icon: isDark ? Icons.dark_mode : Icons.light_mode,
                    title: 'Karanlık Mod',
                    trailing: Switch(
                      value: isDark,
                      onChanged: (val) {
                        ref.read(themeModeProvider.notifier).toggleTheme();
                      },
                      activeColor: AppColors.primaryGreen,
                    ),
                    onTap: () {
                      ref.read(themeModeProvider.notifier).toggleTheme();
                    },
                  );
                },
              ),

              const SizedBox(height: 24),
              _buildSectionHeader(context, 'HAKKINDA'),

              /// ℹ️ UYGULAMA HAKKINDA
              _SettingsTile(
                icon: Icons.info_outline,
                title: 'Uygulama Hakkında',
                onTap: () {
                  showAboutDialog(
                    context: context,
                    applicationName: 'KaBOOK',
                    applicationVersion: '1.0.0',
                    applicationLegalese: '© 2024 KaBOOK',
                    children: [
                      const SizedBox(height: 16),
                      const Text('KaBOOK, üniversite öğrencileri için geliştirilmiş sosyal medya platformudur.'),
                    ],
                  );
                },
              ),

              const SizedBox(height: 24),
              _buildSectionHeader(context, 'DİĞER'),

              /// 🚪 LOGOUT
              _SettingsTile(
                icon: Icons.logout,
                title: 'Çıkış Yap',
                color: Colors.redAccent,
                onTap: () async {
                  final confirm = await _confirmLogout(context);
                  if (!confirm) return;

                  await ref.read(authServiceProvider).logout();

                  ref.invalidate(currentUserProvider);

                  if (context.mounted) {
                    context.go('/login');
                  }
                },
              ),
            ],
          );
        },
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text('Hata: $e')),
      ),
    );
  }

  /// Bölüm Başlığı
  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.grey,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
      ),
    );
  }

  /// 🔑 CHANGE PASSWORD DIALOG
  void _showChangePasswordDialog(
      BuildContext context, WidgetRef ref) {
    final oldController = TextEditingController();
    final newController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Şifre Değiştir'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldController,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Eski Şifre'),
              ),
              TextField(
                controller: newController,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Yeni Şifre'),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('İptal'),
              onPressed: () => Navigator.pop(ctx),
            ),
            ElevatedButton(
              child: const Text('Kaydet'),
              onPressed: () async {
                try {
                  await ref.read(authServiceProvider).changePassword(
                        oldPassword: oldController.text,
                        newPassword: newController.text,
                      );

                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Şifre başarıyla değiştirildi'),
                      ),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Hata: $e')),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  /// ❓ LOGOUT CONFIRM
  Future<bool> _confirmLogout(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Çıkış Yap'),
            content:
                const Text('Oturumu kapatmak istiyor musun?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Çıkış Yap'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

/// ================= TILE =================
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? color;
  final Widget? trailing; // Yeni: Custom trailing widget desteği

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.color,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0, // Daha düz tasarım
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: color ?? AppColors.primaryGreen),
        title: Text(
          title,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: trailing ?? const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
