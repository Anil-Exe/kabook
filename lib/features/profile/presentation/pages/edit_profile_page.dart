import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../services/appwrite_service.dart'; // Client ve Account için
import '../../../auth/data/auth_providers.dart'; // userProvider için
import '../../../../services/image_upload_service.dart'; // MediaService
import '../../../../utils/custom_popup.dart';

class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();

  XFile? _pickedImage;
  Uint8List? _imageBytes; // Web ve Mobile uyumlu önizleme için
  bool _isUploading = false;

  String? _currentUserId;
  Map<String, dynamic>? _currentProfile;

  String? _selectedUniversity;
  String? _selectedFaculty;
  String? _selectedDepartment;

  bool? _isUsernameAvailable;
  bool _isCheckingUsername = false;
  Timer? _debounce;

  final List<String> _universities = [
    'Kastamonu Üniversitesi',
  ];

  final List<String> _faculties = [
    'Mühendislik ve Mimarlık Fakültesi',
    'Eğitim Fakültesi',
    'Fen Edebiyat Fakültesi',
    'İktisadi ve İdari Bilimler Fakültesi',
    'İlahiyat Fakültesi',
    'İletişim Fakültesi',
    'Orman Fakültesi',
    'Sağlık Bilimleri Fakültesi',
    'Turizm Fakültesi',
    'Güzel Sanatlar ve Tasarım Fakültesi',
    'Spor Bilimleri Fakültesi',
    'Veteriner Fakültesi',
    'Tıp Fakültesi',
    'Diş Hekimliği Fakültesi',
    'Sivil Havacılık Yüksekokulu',
    'Yabancı Diller Yüksekokulu',
    'Meslek Yüksekokulu',
    'Diğer',
  ];

  final List<String> _departments = [
    'Bilgisayar Mühendisliği',
    'Elektrik-Elektronik Mühendisliği',
    'Makine Mühendisliği',
    'İnşaat Mühendisliği',
    'Genetik ve Biyomühendislik',
    'Peyzaj Mimarlığı',
    'Hemşirelik',
    'Ebelik',
    'Beslenme ve Diyetetik',
    'İlahiyat',
    'İlköğretim Matematik Öğretmenliği',
    'Sınıf Öğretmenliği',
    'Türkçe Öğretmenliği',
    'Sosyal Bilgiler Öğretmenliği',
    'Fen Bilgisi Öğretmenliği',
    'Rehberlik ve Psikolojik Danışmanlık',
    'Tarih',
    'Coğrafya',
    'Türk Dili ve Edebiyatı',
    'Matematik',
    'Biyoloji',
    'Fizik',
    'Kimya',
    'İşletme',
    'İktisat',
    'Siyaset Bilimi ve Kamu Yönetimi',
    'Uluslararası İlişkiler',
    'Gazetecilik',
    'Halkla İlişkiler ve Tanıtım',
    'Radyo, Televizyon ve Sinema',
    'Orman Mühendisliği',
    'Orman Endüstri Mühendisliği',
    'Turizm İşletmeciliği',
    'Gastronomi ve Mutfak Sanatları',
    'Grafik Tasarımı',
    'Resim',
    'Müzik',
    'Antrenörlük Eğitimi',
    'Beden Eğitimi ve Spor Öğretmenliği',
    'Spor Yöneticiliği',
    'Tıp',
    'Diş Hekimliği',
    'Bilgisayar Programcılığı',
    'Elektrik',
    'Makine',
    'İnşaat',
    'Muhasebe ve Vergi Uygulamaları',
    'Çocuk Gelişimi',
    'Tıbbi Dokümantasyon ve Sekreterlik',
    'İlk ve Acil Yardım',
    'Anestezi',
    'Tıbbi Laboratuvar Teknikleri',
    'Diğer',
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentUserAndProfile();
  }

  Future<void> _loadCurrentUserAndProfile() async {
    try {
      final user = await Account(AppwriteService.client).get();
      final userId = user.$id;

      final profileDoc = await ref.read(userProvider(userId).future);
      final profile = profileDoc.data;

      setState(() {
        _currentUserId = userId;
        _currentProfile = profile;
        _displayNameController.text = profile['displayName'] ?? '';
        _usernameController.text = profile?['username'] ?? '';
        _bioController.text = profile?['bio'] ?? '';
        
        String? univ = profile['university'];
        if (univ != null && univ.isNotEmpty) {
           if (!_universities.contains(univ)) _universities.add(univ);
           _selectedUniversity = univ;
        }
        String? fac = profile['faculty'];
        if (fac != null && fac.isNotEmpty) {
           if (!_faculties.contains(fac)) _faculties.add(fac);
           _selectedFaculty = fac;
        }
        String? dept = profile['department'];
        if (dept != null && dept.isNotEmpty) {
           if (!_departments.contains(dept)) _departments.add(dept);
           _selectedDepartment = dept;
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Profil yüklenemedi: $e')),
      );
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    if (_currentUserId == null) return;

    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (picked == null) return;

    final bytes = await picked.readAsBytes();

    setState(() {
      _pickedImage = picked;
      _imageBytes = bytes;
      _isUploading = true;
    });

    try {
      // 1. Yeni fotoğrafı yükle
      final inputFile = await MediaService.createInputFile(picked);
      final String newPhotoId = await ref
          .read(authServiceProvider)
          .uploadProfilePhotoFile(inputFile);

      // 2. Eski fotoğrafı silmeye gerek yok (Log tutuyoruz veya permission izin vermeyebilir)
      // İsteğe bağlı: Storage delete izni varsa silinebilir.

      // 3. DB'de YENİ VERSİYON oluştur (Append-Only)
      if (_currentProfile == null) throw Exception("Profil verisi bulunamadı");

      await ref.read(authServiceProvider).createProfileVersion(
            userId: _currentUserId!,
            oldProfileData: _currentProfile!,
            newPhotoId: newPhotoId, // 🟢 ID gönderiyoruz
            // Diğer alanlar mevcut haliyle kopyalanır (createProfileVersion içinde)
          );

      // 4. Yerel state güncelle
      setState(() {
        _currentProfile?['photoId'] = newPhotoId;
      });

      // 🔥 Profil sayfasını yenile
      ref.invalidate(userProvider(_currentUserId!));

      if (mounted) {
        await CustomPopup.showSuccess(
          context: context,
          title: 'Güncellendi',
          message: 'Profil fotoğrafın başarıyla yenilendi! 🚀',
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  void _onUsernameChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    if (value.isEmpty || value == _currentProfile?['username']) {
      setState(() {
        _isUsernameAvailable = null;
        _isCheckingUsername = false;
      });
      return;
    }

    setState(() => _isCheckingUsername = true);

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final isAvailable = await ref.read(authServiceProvider).checkUsernameAvailability(value);
        if (mounted) {
          setState(() {
            _isUsernameAvailable = isAvailable;
            _isCheckingUsername = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _isCheckingUsername = false);
      }
    });
  }

  Future<void> _saveProfile() async {
    if (_currentUserId == null) return;

    try {
      // 1. Kullanıcı Adı Değişikliği Kontrolü
      final newUsername = _usernameController.text.trim();
      final oldUsername = _currentProfile?['username'];
      String? usernameToSave;
      String? lastChangedToSave;

      if (newUsername.isNotEmpty && newUsername != oldUsername) {
        // Onay Dialogu
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Kullanıcı Adını Değiştir'),
            content: const Text('Kullanıcı adını değiştirmek istediğine emin misin? Bu işlemi sadece 30 günde bir yapabilirsin.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Evet, Değiştir')),
            ],
          ),
        );

        if (confirm != true) return;

        // 30 Gün Kontrolü
        final lastChangedStr = _currentProfile?['usernameLastChangedAt'];
        if (lastChangedStr != null) {
          final lastChanged = DateTime.parse(lastChangedStr);
          final difference = DateTime.now().difference(lastChanged).inDays;
          if (difference < 30) {
            throw Exception('Kullanıcı adını 30 günde bir değiştirebilirsin. ${30 - difference} gün daha beklemen gerekiyor.');
          }
        }

        // Müsaitlik Kontrolü (Son bir kez daha)
        final isAvailable = await ref.read(authServiceProvider).checkUsernameAvailability(newUsername);
        if (!isAvailable) {
          throw Exception('Bu kullanıcı adı zaten kullanımda.');
        }

        usernameToSave = newUsername;
        lastChangedToSave = DateTime.now().toIso8601String();
      }

      // 2. Diğer Profil Bilgilerini Güncelle
      await ref.read(authServiceProvider).createProfileVersion(
            userId: _currentUserId!,
            oldProfileData: _currentProfile!,
            newDisplayName: _displayNameController.text.trim(),
            newBio: _bioController.text.trim(),
            newUniversity: _selectedUniversity,
            newFaculty: _selectedFaculty,
            newDepartment: _selectedDepartment,
            newUsername: usernameToSave,
            newUsernameLastChangedAt: lastChangedToSave,
          );

      // Yerel state güncellemeye gerek yok, sayfa yenilenecek veya çıkılacak

      // 🔥 Profil sayfasını yenile
      ref.invalidate(userProvider(_currentUserId!));

      if (mounted) {
        await CustomPopup.showSuccess(
          context: context,
          title: 'Güncellendi',
          message: 'Profil bilgilerin başarıyla kaydedildi.',
        );
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydedilemedi: $e')),
      );
    }
  }

  @override
  void dispose() {
    _bioController.dispose();
    _displayNameController.dispose();
    _usernameController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil Düzenle'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveProfile,
          ),
        ],
      ),
      body: _currentProfile == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickAndUploadPhoto,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircleAvatar(
                          radius: 80,
                          backgroundImage: _imageBytes != null
                              ? MemoryImage(_imageBytes!) as ImageProvider
                              : _currentProfile?['photoId'] != null
                                  ? CachedNetworkImageProvider(
                                      MediaService.getFileUrl(_currentProfile!['photoId']))
                                  : const AssetImage(
                                      'assets/default_avatar.png'), // Assets'e ekle
                          child: _currentProfile?['photoId'] == null &&
                                  _imageBytes == null
                              ? const Icon(Icons.person,
                                  size: 80, color: Colors.grey)
                              : null,
                        ),
                        if (_isUploading)
                          const Positioned.fill(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 4,
                            ),
                          ),
                        const Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            radius: 24,
                            backgroundColor: Colors.green,
                            child:
                                Icon(Icons.camera_alt, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  
                  // Kullanıcı Adı
                  TextField(
                    controller: _usernameController,
                    onChanged: _onUsernameChanged,
                    decoration: InputDecoration(
                      labelText: 'Kullanıcı Adı',
                      border: const OutlineInputBorder(),
                      suffixIcon: _isCheckingUsername
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : _isUsernameAvailable == true
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : _isUsernameAvailable == false
                                  ? const Icon(Icons.cancel, color: Colors.red)
                                  : null,
                      helperText: _isUsernameAvailable == false 
                          ? 'Bu kullanıcı adı kullanımda' 
                          : '30 günde bir değiştirebilirsiniz',
                      helperStyle: TextStyle(color: _isUsernameAvailable == false ? Colors.red : Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Ad Soyad
                  TextField(
                    controller: _displayNameController,
                    decoration: const InputDecoration(labelText: 'Ad Soyad', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 20),

                  // Bio
                  TextField(
                    controller: _bioController,
                    decoration: const InputDecoration(
                      labelText: 'Bio',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 4,
                    maxLength: 200,
                  ),
                  const SizedBox(height: 20),

                  // Akademik Bilgiler
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Akademik Bilgiler', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
                  ),
                  const SizedBox(height: 10),
                  
                  DropdownButtonFormField<String>(
                    value: _selectedUniversity,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Üniversite', border: OutlineInputBorder()),
                    items: _universities.map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      setState(() => _selectedUniversity = newValue);
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedFaculty,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Fakülte / Yüksekokul', border: OutlineInputBorder()),
                    items: _faculties.map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      setState(() => _selectedFaculty = newValue);
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedDepartment,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Bölüm', border: OutlineInputBorder()),
                    items: _departments.map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      setState(() => _selectedDepartment = newValue);
                    },
                  ),

                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isUploading ? null : _saveProfile,
                      child: const Text('Değişiklikleri Kaydet'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}