import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/layout/search_providers.dart';
import '../../../../services/image_upload_service.dart';
import '../../data/message_providers.dart';
import '../../../auth/data/auth_providers.dart';
import 'chat_page.dart';

class NewChatSearchPage extends ConsumerStatefulWidget {
  const NewChatSearchPage({super.key});

  @override
  ConsumerState<NewChatSearchPage> createState() => _NewChatSearchPageState();
}

class _NewChatSearchPageState extends ConsumerState<NewChatSearchPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(searchUsersProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Kime mesaj göndereceksin?',
            border: InputBorder.none,
          ),
          onChanged: (val) {
            ref.read(searchQueryProvider.notifier).state = val;
          },
        ),
      ),
      body: usersAsync.when(
        data: (users) {
          if (users.isEmpty) {
            return const Center(child: Text('Kullanıcı bulunamadı'));
          }
          
          final currentUser = ref.read(currentUserProvider).value;

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final data = user.data;
              
              // 🔥 DÜZELTME: Kendi hesabını listede gösterme
              if (currentUser != null && data['userId'] == currentUser.$id) {
                return const SizedBox.shrink();
              }

              final photoId = data['photoId'];

              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: photoId != null
                      ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId))
                      : null,
                  child: photoId == null ? const Icon(Icons.person) : null,
                ),
                title: Text(data['displayName'] ?? 'İsimsiz'),
                subtitle: Text('@${data['username'] ?? ''}'),
                onTap: () async {
                  final targetAccountId = data['userId'] as String;

                  if (currentUser != null) {
                    // Yükleniyor göster
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (c) => const Center(child: CircularProgressIndicator()),
                    );

                    try {
                      // 1. Sohbeti Getir veya Oluştur
                      final chatDoc = await ref.read(messageServiceProvider).getOrCreateDirectChat(
                        currentUserId: currentUser.$id,
                        targetUserId: targetAccountId,
                      );

                      // 2. Sohbet Sayfasına Git
                      if (context.mounted) {
                        Navigator.pop(context); // Dialogu kapat
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatPage(
                              chatId: chatDoc.$id,
                              chatTitle: data['displayName'] ?? 'Sohbet',
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        Navigator.pop(context); // Dialogu kapat
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
                      }
                    }
                  }
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hata: $e')),
      ),
    );
  }
}