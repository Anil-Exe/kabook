import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:appwrite/appwrite.dart';
import '../../../../core/config/appwrite_config.dart';
import '../../../../services/appwrite_service.dart';
import '../../data/providers/event_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/data/auth_providers.dart';
import 'package:url_launcher/url_launcher.dart'; // Harita testi için
import '../../../../utils/custom_popup.dart';

class CreateEventPage extends ConsumerStatefulWidget {
  const CreateEventPage({super.key});

  @override
  ConsumerState<CreateEventPage> createState() => _CreateEventPageState();
}

class _CreateEventPageState extends ConsumerState<CreateEventPage> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _locationController;
  late TextEditingController _maxParticipantsController;
  
  // State
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _isLoading = false;
  XFile? _pickedImage;
  
  String _selectedCategory = 'Diğer';
  final List<String> _categories = ['Müzik', 'Spor', 'Sanat', 'Eğitim', 'Teknoloji', 'Gezi', 'Yeme-İçme', 'Diğer'];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
    _locationController = TextEditingController();
    _maxParticipantsController = TextEditingController(text: '50');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _maxParticipantsController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _pickedImage = image);
    }
  }

  /// Girilen konumu haritada test et
  Future<void> _testLocation() async {
    final location = _locationController.text.trim();
    if (location.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen önce bir konum yazın')),
      );
      return;
    }
    final query = Uri.encodeComponent(location);
    final googleMapsUrl = Uri.parse("https://www.google.com/maps/search/?api=1&query=$query");
    if (!await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Harita açılamadı')),
        );
      }
    }
  }

  Future<void> _createEvent() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen tarih ve saat seçin')),
      );
      return;
    }

    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Oturum açmanız gerekiyor')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final eventDate = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );

      String? imageId;

      if (_pickedImage != null) {
        final inputFile = InputFile.fromPath(
          path: _pickedImage!.path,
          filename: _pickedImage!.name,
        );
        final file = await AppwriteService.storage.createFile(
          bucketId: AppwriteConfig.storageBucketId,
          fileId: ID.unique(),
          file: inputFile,
        );
        imageId = file.$id;
      }

      await AppwriteService.databases.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventsCollectionId,
        documentId: ID.unique(),
        data: {
          'title': _titleController.text.trim(),
          'description': _descriptionController.text.trim(),
          'location': _locationController.text.trim(),
          'eventDate': eventDate.toIso8601String(),
          'maxParticipants': int.tryParse(_maxParticipantsController.text) ?? 50,
          'creatorId': currentUser.$id,
          'imageId': imageId,
          'participantsCount': 0,
          'category': _selectedCategory,
        },
        // permissions parametresi kaldırıldı. Appwrite Console'dan yönetilmeli.
      );

      // Refresh providers
      ref.invalidate(eventsProvider);

      if (mounted) {
        await CustomPopup.showSuccess(
          context: context,
          title: 'Kutlarız!',
          message: 'Etkinliğin başarıyla oluşturuldu.',
        );
        
        if (mounted) context.pop();
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
    return Scaffold(
      appBar: AppBar(title: const Text('Etkinlik Oluştur')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                    image: _pickedImage != null
                        ? DecorationImage(
                            image: FileImage(File(_pickedImage!.path)),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _pickedImage == null
                      ? const Center(
                          child: Icon(Icons.add_photo_alternate, size: 50, color: Colors.grey),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Etkinlik Başlığı',
                  prefixIcon: Icon(Icons.title),
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Başlık gerekli' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Açıklama',
                  prefixIcon: Icon(Icons.description),
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Kategori',
                  prefixIcon: Icon(Icons.category),
                  border: OutlineInputBorder(),
                ),
                items: _categories.map((String category) {
                  return DropdownMenuItem<String>(
                    value: category,
                    child: Text(category),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() => _selectedCategory = newValue);
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _locationController,
                decoration: InputDecoration(
                  labelText: 'Konum (Adres veya Mekan Adı)',
                  hintText: 'Örn: Taksim Meydanı, İstanbul',
                  prefixIcon: const Icon(Icons.location_on),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.map, color: AppColors.primaryGreen),
                    tooltip: 'Haritada Kontrol Et',
                    onPressed: _testLocation,
                  ),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Konum gerekli' : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _selectDate(context),
                      icon: const Icon(Icons.calendar_today),
                      label: Text(_selectedDate == null ? 'Tarih' : DateFormat('d MMM yyyy').format(_selectedDate!)),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _selectTime(context),
                      icon: const Icon(Icons.access_time),
                      label: Text(_selectedTime == null ? 'Saat' : '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _maxParticipantsController,
                decoration: const InputDecoration(
                  labelText: 'Maksimum Katılımcı',
                  prefixIcon: Icon(Icons.people),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) => v == null || v.isEmpty ? 'Sayı gerekli' : null,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _createEvent,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Etkinlik Oluştur', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}