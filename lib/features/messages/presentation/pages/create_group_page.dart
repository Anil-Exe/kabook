import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:appwrite/appwrite.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/config/appwrite_config.dart';
import '../../../../services/image_upload_service.dart';
import '../../../../services/appwrite_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../follow/data/follow_service.dart';
import '../../data/message_providers.dart';

class CreateGroupPage extends ConsumerStatefulWidget {
  const CreateGroupPage({super.key});

  @override
  ConsumerState<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends ConsumerState<CreateGroupPage> {
  final _groupNameController = TextEditingController();
  final Set<String> _selectedUserIds = {};
  bool _isLoading = false;
  XFile? _selectedImage;

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      setState(() {
        _selectedImage = image;
      });
    }
  }

  Future<void> _createGroup() async {
    if (_groupNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen grup adı girin')),
      );
      return;
    }
    if (_selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('En az bir kişi seçmelisiniz')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final currentUser = ref.read(currentUserProvider).value;
      if (currentUser == null) return;

      // Katılımcılar: Ben + Seçilenler
      final participants = [currentUser.$id, ..._selectedUserIds];

      // Resim Yükleme İşlemi
      String? uploadedImageId;
      if (_selectedImage != null) {
        final storage = Storage(AppwriteService.client);
        final inputFile = await MediaService.createInputFile(_selectedImage!);
        
        final file = await storage.createFile(
          bucketId: AppwriteConfig.storageBucketId,
          fileId: ID.unique(),
          file: inputFile,
        );
        uploadedImageId = file.$id;
      }

      final chatDoc = await ref.read(messageServiceProvider).createChat(
        participantIds: participants,
        type: 'group',
        groupName: _groupNameController.text.trim(),
        creatorId: currentUser.$id,
        groupImageId: uploadedImageId,
      );

      if (mounted) {
        context.pop(); // Bu sayfayı kapat
        context.push('/chat/${chatDoc.$id}', extra: _groupNameController.text.trim());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yeni Grup'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _createGroup,
            child: _isLoading 
              ? const CircularProgressIndicator.adaptive() 
              : const Text('Oluştur', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Grup Bilgileri
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _pickImage,
                  child: CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: _selectedImage != null 
                        ? FileImage(File(_selectedImage!.path)) 
                        : null,
                    child: _selectedImage == null ? const Icon(Icons.camera_alt, color: Colors.grey) : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _groupNameController,
                    decoration: const InputDecoration(
                      hintText: 'Grup Adı',
                      border: UnderlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Katılımcı Ekle', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),

          // Takip Edilenler Listesi
          Expanded(
            child: currentUser == null 
              ? const SizedBox.shrink()
              : FutureBuilder(
                  future: ref.read(followServiceProvider).getFollowing(currentUser.$id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    
                    final users = snapshot.data ?? [];
                    if (users.isEmpty) {
                      return const Center(child: Text('Takip ettiğiniz kimse yok.'));
                    }

                    return ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final doc = users[index];
                        final targetUserId = doc.data['followingId'];

                        // Kullanıcı detayını çek (Follow tablosunda sadece ID var)
                        return Consumer(
                          builder: (context, ref, _) {
                            final userAsync = ref.watch(userProfileProvider(targetUserId));
                            
                            return userAsync.when(
                              data: (userData) {
                                if (userData == null) return const SizedBox.shrink();
                                
                                final name = userData['displayName'] ?? 'Kullanıcı';
                                final photoId = userData['photoId'] ?? userData['profileImageUrl'];
                                final isSelected = _selectedUserIds.contains(targetUserId);

                                return ListTile(
                                  leading: Stack(
                                    children: [
                                      CircleAvatar(
                                        backgroundImage: photoId != null 
                                          ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId)) 
                                          : null,
                                        child: photoId == null ? Text(name[0]) : null,
                                      ),
                                      if (isSelected)
                                        const Positioned(
                                          right: 0,
                                          bottom: 0,
                                          child: CircleAvatar(
                                            radius: 10,
                                            backgroundColor: AppColors.primaryGreen,
                                            child: Icon(Icons.check, size: 12, color: Colors.white),
                                          ),
                                        ),
                                    ],
                                  ),
                                  title: Text(name),
                                  onTap: () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedUserIds.remove(targetUserId);
                                      } else {
                                        _selectedUserIds.add(targetUserId);
                                      }
                                    });
                                  },
                                );
                              },
                              loading: () => const ListTile(title: Text('Yükleniyor...')),
                              error: (_,__) => const SizedBox.shrink(),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}
