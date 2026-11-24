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

class EditEventPage extends ConsumerStatefulWidget {
  final String eventId;
  const EditEventPage({super.key, required this.eventId});

  @override
  ConsumerState<EditEventPage> createState() => _EditEventPageState();
}

class _EditEventPageState extends ConsumerState<EditEventPage> {
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
  bool _isInitialized = false;
  XFile? _pickedImage;
  String? _currentImageId;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
    _locationController = TextEditingController();
    _maxParticipantsController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _maxParticipantsController.dispose();
    super.dispose();
  }

  void _initializeControllers(event) {
    if (_isInitialized) return;
    
    _titleController.text = event.title;
    _descriptionController.text = event.description ?? ''; 
    _locationController.text = event.location;
    _maxParticipantsController.text = (event.maxParticipants ?? 50).toString();
    
    _selectedDate = event.eventDate;
    _selectedTime = TimeOfDay.fromDateTime(event.eventDate);
    _currentImageId = event.imageId;
    
    _isInitialized = true;
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
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
      initialTime: _selectedTime ?? TimeOfDay.now(),
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

  Future<void> _saveEvent() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen tarih ve saat seçin')),
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

      String? finalImageId = _currentImageId;

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
        finalImageId = file.$id;
      }

      await AppwriteService.databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.eventsCollectionId,
        documentId: widget.eventId,
        data: {
          'title': _titleController.text.trim(),
          'description': _descriptionController.text.trim(),
          'location': _locationController.text.trim(),
          'eventDate': eventDate.toIso8601String(),
          'maxParticipants': int.tryParse(_maxParticipantsController.text) ?? 50,
          'imageId': finalImageId,
        },
      );

      // Refresh providers
      ref.invalidate(eventDetailsProvider(widget.eventId));
      ref.invalidate(eventsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Etkinlik başarıyla güncellendi')),
        );
        context.pop(); // Go back to details
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
    final eventAsync = ref.watch(eventDetailsProvider(widget.eventId));

    return Scaffold(
      appBar: AppBar(title: const Text('Etkinliği Düzenle')),
      body: eventAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (event) {
          _initializeControllers(event);

          return SingleChildScrollView(
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
                            : (_currentImageId != null
                                ? DecorationImage(
                                    image: NetworkImage(AppwriteService.getFilePreviewUrl(_currentImageId!).replaceAll('/preview', '/view')),
                                    fit: BoxFit.cover,
                                  )
                                : null),
                      ),
                      child: _pickedImage == null && _currentImageId == null
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
                  TextFormField(
                    controller: _locationController,
                    decoration: const InputDecoration(
                      labelText: 'Konum',
                      prefixIcon: Icon(Icons.location_on),
                      border: OutlineInputBorder(),
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
                    onPressed: _isLoading ? null : _saveEvent,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Değişiklikleri Kaydet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}