import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:appwrite/appwrite.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/appwrite_config.dart';
import '../../../../services/appwrite_service.dart';
import '../../../../services/image_upload_service.dart';

class ChatMediaPage extends ConsumerWidget {
  final String chatId;

  const ChatMediaPage({super.key, required this.chatId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Medya, Belge ve Bağlantılar'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Medya'),
              Tab(text: 'Belgeler'),
              Tab(text: 'Bağlantılar'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _MediaTab(chatId: chatId),
            _DocsTab(chatId: chatId),
            _LinksTab(chatId: chatId),
          ],
        ),
      ),
    );
  }
}

class _MediaTab extends StatelessWidget {
  final String chatId;
  const _MediaTab({required this.chatId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: AppwriteService.databases.listDocuments(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.messagesCollectionId,
          queries: [
            Query.equal('chatId', chatId),
            Query.equal('messageType', ['image', 'video']), // Resim ve Videolar
            Query.orderDesc('\$createdAt'),
          ],
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Hata: ${snapshot.error}'));
          }

          final docs = snapshot.data?.documents ?? [];

          if (docs.isEmpty) {
            return const Center(child: Text('Henüz medya yok.'));
          }

          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data;
              final fileId = data['fileId'];
              final type = data['messageType'];

              if (fileId == null) return const SizedBox.shrink();

              final imageUrl = MediaService.getFileUrl(fileId);

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        backgroundColor: Colors.black,
                        appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
                        body: Center(child: InteractiveViewer(child: CachedNetworkImage(imageUrl: imageUrl))),
                      ),
                    ),
                  );
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover),
                    if (type == 'video')
                      const Center(child: Icon(Icons.play_circle_outline, color: Colors.white, size: 40)),
                  ],
                ),
              );
            },
          );
        },
    );
  }
}

class _DocsTab extends StatelessWidget {
  final String chatId;
  const _DocsTab({required this.chatId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: AppwriteService.databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.messagesCollectionId,
        queries: [
          Query.equal('chatId', chatId),
          Query.equal('messageType', 'file'),
          Query.orderDesc('\$createdAt'),
        ],
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data?.documents ?? [];
        if (docs.isEmpty) return const Center(child: Text('Henüz belge yok.'));

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data;
            final name = data['content'] ?? 'Belge';
            final fileId = data['fileId'];

            return ListTile(
              leading: const Icon(Icons.insert_drive_file, color: Colors.blue),
              title: Text(name),
              onTap: () {
                if (fileId != null) {
                  launchUrl(Uri.parse(MediaService.getFileUrl(fileId)), mode: LaunchMode.externalApplication);
                }
              },
            );
          },
        );
      },
    );
  }
}

class _LinksTab extends StatelessWidget {
  final String chatId;
  const _LinksTab({required this.chatId});

  @override
  Widget build(BuildContext context) {
    // Not: Appwrite'da 'contains' sorgusu için full-text index gerekir.
    // Basitlik adına tüm text mesajlarını çekip client-side filtreliyoruz.
    return FutureBuilder(
      future: AppwriteService.databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.messagesCollectionId,
        queries: [
          Query.equal('chatId', chatId),
          Query.equal('messageType', 'text'),
          Query.orderDesc('\$createdAt'),
          Query.limit(100), // Performans için limit
        ],
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        
        final docs = snapshot.data?.documents ?? [];
        // İçinde http geçen mesajları filtrele
        final linkDocs = docs.where((doc) {
          final content = (doc.data['content'] ?? '').toString();
          return content.contains('http');
        }).toList();

        if (linkDocs.isEmpty) return const Center(child: Text('Henüz bağlantı yok.'));

        return ListView.builder(
          itemCount: linkDocs.length,
          itemBuilder: (context, index) {
            final content = linkDocs[index].data['content'] as String;
            // Basit URL çıkarımı
            final url = RegExp(r'https?://\S+').firstMatch(content)?.group(0);

            return ListTile(
              leading: const Icon(Icons.link, color: Colors.grey),
              title: Text(url ?? content, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(content, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () {
                if (url != null) {
                  launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                }
              },
            );
          },
        );
      },
    );
  }
}