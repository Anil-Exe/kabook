import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'story_editor_page.dart';

class StoryCameraPage extends StatefulWidget {
  const StoryCameraPage({super.key});

  @override
  State<StoryCameraPage> createState() => _StoryCameraPageState();
}

class _StoryCameraPageState extends State<StoryCameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  int _selectedCameraIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    var status = await Permission.camera.request();
    if (!status.isGranted) return;

    _cameras = await availableCameras();
    if (_cameras != null && _cameras!.isNotEmpty) {
      _controller = CameraController(
        _cameras![_selectedCameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _controller!.initialize();
      if (mounted) setState(() => _isCameraInitialized = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (!_isCameraInitialized || _controller == null) return;
    try {
      final image = await _controller!.takePicture();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StoryEditorPage(file: File(image.path), isVideo: false),
        ),
      );
    } catch (e) {
      debugPrint("Fotoğraf çekme hatası: $e");
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final media = await picker.pickMedia();
    if (media != null && mounted) {
      final isVideo = media.path.toLowerCase().endsWith('.mp4') || media.path.toLowerCase().endsWith('.mov');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StoryEditorPage(file: File(media.path), isVideo: isVideo),
        ),
      );
    }
  }

  void _switchCamera() {
    if (_cameras == null || _cameras!.length < 2) return;
    setState(() {
      _isCameraInitialized = false;
      _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras!.length;
    });
    _initCamera();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _controller == null) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Kamera Önizleme
          Center(child: CameraPreview(_controller!)),

          // Üst Butonlar (Kapat)
          Positioned(
            top: 50,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () {
                // Ana sayfaya dön
                if (Navigator.canPop(context)) Navigator.pop(context);
              },
            ),
          ),

          // Alt Kontroller
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Galeri
                GestureDetector(
                  onTap: _pickFromGallery,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.black54,
                    ),
                    child: const Icon(Icons.photo_library, color: Colors.white, size: 20),
                  ),
                ),

                // Çekim Butonu
                GestureDetector(
                  onTap: _takePicture,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    ),
                  ),
                ),

                // Kamera Değiştir
                IconButton(
                  icon: const Icon(Icons.flip_camera_ios, color: Colors.white, size: 30),
                  onPressed: _switchCamera,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
