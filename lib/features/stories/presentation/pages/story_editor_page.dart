import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screenshot/screenshot.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:scribble/scribble.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../data/story_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../widgets/story_feed_widgets.dart';
import '../../../profile/presentation/pages/profile_page.dart';
import 'dart:math' as math;
import '../../../../utils/custom_popup.dart';

// Sürüklenebilir öğeleri takip etmek için model
class OverlayItem {
  final String id;
  Widget widget;
  Offset position;
  double scale;
  double rotation;
  OverlayItem({
    required this.id,
    required this.widget,
    required this.position,
    this.scale = 1.0,
    this.rotation = 0.0,
  });
}

class StoryEditorPage extends ConsumerStatefulWidget {
  final File file;
  final bool isVideo;

  const StoryEditorPage({super.key, required this.file, required this.isVideo});

  @override
  ConsumerState<StoryEditorPage> createState() => _StoryEditorPageState();
}

class _StoryEditorPageState extends ConsumerState<StoryEditorPage> {
  final TextEditingController _captionController = TextEditingController();
  final ScreenshotController _screenshotController = ScreenshotController();
  bool _isUploading = false;
  String? _location;
  late final ScribbleNotifier _scribbleNotifier;
  bool _isDrawing = false;
  bool _isTextEditing = false;
  bool _isDragging = false; // Sürükleme durumu
  bool _isDeleteActive = false; // Silme alanı üzerinde mi?
  double _strokeWidth = 5.0; // Kalem kalınlığı
  
  // Filtre Değişkenleri
  int _selectedFilterIndex = 0;
  final List<List<double>> _filters = [
    [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0], // Normal
    [0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0, 0, 0, 1, 0], // Siyah-Beyaz
    [0.393, 0.769, 0.189, 0, 0, 0.349, 0.686, 0.168, 0, 0, 0.272, 0.534, 0.131, 0, 0, 0, 0, 0, 1, 0], // Sepya
    [1.2, 0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 0, 0.8, 0, 0, 0, 0, 0, 1, 0], // Sıcak (Vintage)
    [0.8, 0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 0, 1.2, 0, 0, 0, 0, 0, 1, 0], // Soğuk (Cyan)
  ];
  final List<String> _filterNames = ['Normal', 'Siyah-Beyaz', 'Sepya', 'Sıcak', 'Soğuk'];

  // İki parmakla yakınlaştırma/döndürme referansları
  double _baseScaleFactor = 1.0;
  double _baseRotationFactor = 0.0;

  // Medya Oynatıcıları
  VideoPlayerController? _videoController;
  final AudioPlayer _bgAudioPlayer = AudioPlayer();

  // Yazı Editörü Değişkenleri
  Color _selectedTextColor = Colors.white;
  bool _isTextBackground = false; // Arka plan rengi açık mı?
  double _textSize = 24.0;
  TextAlign _textAlign = TextAlign.center;
  int _selectedFontIndex = 0;

  // Seçilen Müzik Verileri
  String? _selectedMusicUrl;
  String? _selectedMusicTitle;

  final List<Map<String, TextStyle>> _fontOptions = [
    {'Klasik': const TextStyle(fontWeight: FontWeight.bold)},
    {'Modern': const TextStyle(fontFamily: 'sans-serif', fontWeight: FontWeight.w900, letterSpacing: 1.2)},
    {'Daktilo': const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)},
    {'El Yazısı': const TextStyle(fontFamily: 'cursive', fontWeight: FontWeight.bold)},
    {'Serif': const TextStyle(fontFamily: 'serif', fontStyle: FontStyle.italic, fontWeight: FontWeight.bold)},
  ];
  
  // Eklenen overlay öğeleri (Yazı, Sticker vb.)
  List<OverlayItem> _overlayItems = [];

  Future<void> _shareStory() async {
    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) return;

    // Eğer çizim modundaysa, çık
    if (_isDrawing) {
      setState(() {
        _isDrawing = false;
      });
    }

    _bgAudioPlayer.stop();
    _videoController?.pause();

    setState(() => _isUploading = true);

    try {
      File fileToUpload = widget.file;

      // Eğer resimse, her şeyi (çizim, yazı, sticker) screenshot alarak birleştir
      if (!widget.isVideo) {
        // Pixel ratio'yu yüksek tutarak kaliteyi koru
        final captured = await _screenshotController.capture(pixelRatio: 2.0);
        if (captured != null) {
          final tempDir = Directory.systemTemp;
          final tempFile = File('${tempDir.path}/story_edited_${DateTime.now().millisecondsSinceEpoch}.png');
          await tempFile.writeAsBytes(captured);
          fileToUpload = tempFile;
        }
      }

      await ref.read(storyServiceProvider).createStory(
        userId: currentUser.$id,
        mediaFile: fileToUpload,
        mediaType: widget.isVideo ? 'video' : 'image',
        duration: 15, // ✨ Hikaye süresi 15 saniyeye çıkarıldı (Müzik daha uzun çalsın)
        caption: _captionController.text,
        location: _location,
        musicUrl: _selectedMusicUrl,
        musicTitle: _selectedMusicTitle,
      );

      // Invalidate providers to refresh the UI
      ref.invalidate(storyFeedDataProvider);
      ref.invalidate(userStoriesProvider(currentUser.$id));

      if (mounted) {
        await CustomPopup.showSuccess(
          context: context,
          title: 'Başarılı!',
          message: 'Hikayen başarıyla paylaşıldı 🚀',
        );
        
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst); // Ana sayfaya kadar her şeyi kapat
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _scribbleNotifier = ScribbleNotifier();
    
    // Eğer video ise oynatıcıyı başlat
    if (widget.isVideo) {
      _videoController = VideoPlayerController.file(widget.file)
        ..initialize().then((_) {
          setState(() {});
          _videoController!.setLooping(true);
          _videoController!.play();
        });
    }
  }

  Future<void> _addLocation() async {
    try {
      // İzin kontrolü
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
      
      String addressText = "${position.latitude.toStringAsFixed(2)}, ${position.longitude.toStringAsFixed(2)}";
      
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          addressText = "${place.subAdministrativeArea ?? place.locality}, ${place.administrativeArea}";
        }
      } catch (e) {
        debugPrint('Geocoding hatası: $e');
      }

      setState(() {
        _location = addressText;
        _addOverlayItem(_buildLocationBadge());
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Konum alınamadı')));
    }
  }

  Widget _buildLocationBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Colors.purple, Colors.orange]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_on, color: Colors.white, size: 20),
          const SizedBox(width: 6),
          Text(_location ?? 'Konum', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, decoration: TextDecoration.none, fontSize: 16)),
        ],
      ),
    );
  }

  // ✨ Yeni Sticker Ekleme Fonksiyonu
  void _addSticker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withOpacity(0.9),
      builder: (context) {
        return SizedBox(
          height: 250,
          child: GridView.count(
            crossAxisCount: 5,
            padding: const EdgeInsets.all(16),
            children: [
              '😀', '😂', '😍', '😎', '🥳', '🔥', '💯', '❤️', '🎉', '👍',
              '🍕', '🍔', '☕', '🚀', '✈️', '🌍', '🐶', '🐱', '🌟', '💡'
            ].map((emoji) {
              return GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  _addOverlayItem(Text(emoji, style: const TextStyle(fontSize: 50)));
                },
                child: Center(child: Text(emoji, style: const TextStyle(fontSize: 32))),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  // ✨ Müzik Ekleme Fonksiyonu
  void _addMusic() {
    // Zaten müzik varsa yenisini eklemeden önce eskisini kaldıralım
    _overlayItems.removeWhere((item) => item.id == 'music_sticker');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212), // Spotify Dark
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: _MusicSearchSheet(
            onSelected: (song, startTime) {
              setState(() {
                _selectedMusicUrl = song['url'];
                _selectedMusicTitle = '${song['title']} - ${song['artist']}';
                
                // Müziği arkada çal ve videoyu sessize al
                _bgAudioPlayer.play(UrlSource(song['url']!));
                if (startTime > 0) {
                  _bgAudioPlayer.seek(Duration(milliseconds: (startTime * 1000).toInt()));
                }
                _bgAudioPlayer.setReleaseMode(ReleaseMode.loop);
                _videoController?.setVolume(0.0);
              });
              
              _addOverlayItem(
                _buildMusicSticker(song['title']!, song['artist']!, song['cover']),
                id: 'music_sticker',
              );
            },
          ),
        );
      }
    );
  }

  Widget _buildMusicSticker(String title, String artist, String? coverUrl) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (coverUrl != null && coverUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(coverUrl, width: 36, height: 36, fit: BoxFit.cover),
            )
          else
            const Icon(Icons.music_note, color: Colors.black, size: 24),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14)),
              Text(artist, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  // ✨ Overlay'e Öğe Ekleme (Merkeze ekler)
  void _addOverlayItem(Widget child, {String? id}) {
    setState(() {
      _overlayItems.add(OverlayItem(
        id: id ?? DateTime.now().toString(),
        widget: child,
        position: Offset(MediaQuery.of(context).size.width / 3, MediaQuery.of(context).size.height / 3),
      ));
    });
  }

  // ✨ Modern Metin Editörü Aç
  void _openTextEditor() {
    setState(() {
      _isTextEditing = true;
      _captionController.clear();
      _isTextBackground = false;
    });
  }

  // ✨ Metni Kaydet ve Ekrana Ekle
  void _saveText() {
    if (_captionController.text.isNotEmpty) {
      _addOverlayItem(
        Text(
          _captionController.text,
          textAlign: _textAlign,
          style: _fontOptions[_selectedFontIndex].values.first.copyWith(
            color: _selectedTextColor,
            backgroundColor: _isTextBackground ? ( _selectedTextColor == Colors.white ? Colors.black54 : _selectedTextColor.withOpacity(0.7)) : null,
            fontSize: _textSize,
            shadows: const [Shadow(blurRadius: 10, color: Colors.black, offset: Offset(2, 2))],
          ),
        ),
      );
    }
    setState(() {
      _isTextEditing = false;
    });
  }

  Widget _buildTextEditor() {
    return Container(
      color: Colors.black.withOpacity(0.4), // ✨ Şeffaflık artırıldı (Instagram gibi)
      child: SafeArea(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Hizalama Butonu (Opsiyonel eklenebilir)
                // Arka Plan Toggle Butonu
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: _isTextBackground ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white)),
                    child: Icon(Icons.text_format, color: _isTextBackground ? Colors.black : Colors.white, size: 20),
                  ),
                  onPressed: () => setState(() => _isTextBackground = !_isTextBackground),
                ),
                IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => setState(() => _isTextEditing = false)),
                IconButton(icon: const Icon(Icons.check, color: Colors.white), onPressed: _saveText),
              ],
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _captionController,
                autofocus: true,
                textAlign: _textAlign,
                style: _fontOptions[_selectedFontIndex].values.first.copyWith(
                  color: _selectedTextColor, 
                  fontSize: _textSize,
                  backgroundColor: _isTextBackground ? ( _selectedTextColor == Colors.white ? Colors.black54 : _selectedTextColor.withOpacity(0.7)) : null,
                ),
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'Yazmaya başla...', hintStyle: TextStyle(color: Colors.grey)),
                maxLines: null,
              ),
            ),
            const Spacer(),
            // Font Seçici
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _fontOptions.length,
                itemBuilder: (context, index) {
                  final fontName = _fontOptions[index].keys.first;
                  final fontStyle = _fontOptions[index].values.first;
                  final isSelected = _selectedFontIndex == index;
                  
                  return GestureDetector(
                    onTap: () => setState(() => _selectedFontIndex = index),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white),
                      ),
                      child: Text(
                        fontName,
                        style: fontStyle.copyWith(
                          color: isSelected ? Colors.black : Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            // Renk Seçici
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [Colors.white, Colors.black, Colors.red, Colors.orange, Colors.yellow, Colors.green, Colors.blue, Colors.purple, Colors.pink]
                    .map((color) => GestureDetector(
                          onTap: () => setState(() => _selectedTextColor = color),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 5),
                            width: 30, height: 30,
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _captionController.dispose();
    _scribbleNotifier.dispose();
    _bgAudioPlayer.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 📸 SCREENSHOT ALANI (Görsel + Çizim + Stickerlar)
          Screenshot(
            controller: _screenshotController,
            child: Stack(
              children: [
                // 1. Ana Görsel/Video
                Center(
                  child: widget.isVideo && _videoController != null && _videoController!.value.isInitialized
                      ? AspectRatio(aspectRatio: _videoController!.value.aspectRatio, child: VideoPlayer(_videoController!))
                      : ColorFiltered(
                          colorFilter: ColorFilter.matrix(_filters[_selectedFilterIndex]),
                          child: Image.file(widget.file, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                        ),
                ),
                // 2. Çizim Katmanı (Scribble)
                if (!widget.isVideo)
                  Positioned.fill(
                    child: IgnorePointer(ignoring: !_isDrawing, child: Scribble(notifier: _scribbleNotifier)),
                  ),
                // 3. Sticker ve Yazılar
                ..._overlayItems.map((item) {
                  return Positioned(
                    left: item.position.dx,
                    top: item.position.dy,
                    child: GestureDetector(
                      onScaleStart: (details) {
                        _baseScaleFactor = item.scale;
                        _baseRotationFactor = item.rotation;
                        setState(() {
                          _isDragging = true;
                          _isDeleteActive = false;
                        });
                      },
                      onScaleUpdate: (details) {
                        setState(() {
                          item.position += details.focalPointDelta;
                          item.scale = (_baseScaleFactor * details.scale).clamp(0.3, 5.0);
                          item.rotation = _baseRotationFactor + details.rotation;
                          
                          // Çöp kutusu ile çarpışma kontrolü
                          final screenHeight = MediaQuery.of(context).size.height;
                          final screenWidth = MediaQuery.of(context).size.width;
                          final trashPos = Offset(screenWidth / 2, screenHeight - 80);
                          final itemPos = Offset(item.position.dx + 20, item.position.dy + 20);
                          
                          final distance = (trashPos - itemPos).distance;
                          _isDeleteActive = distance < 60;
                        });
                      },
                      onScaleEnd: (details) {
                        if (_isDeleteActive) {
                          setState(() {
                            _overlayItems.remove(item);
                            // ✨ Müzik etiketi silindiyse müziği durdur
                            if (item.id == 'music_sticker') {
                              _bgAudioPlayer.stop();
                              _selectedMusicUrl = null;
                              _selectedMusicTitle = null;
                              _videoController?.setVolume(1.0); // Videonun sesini geri aç
                            }
                          });
                        }
                        setState(() {
                          _isDragging = false;
                          _isDeleteActive = false;
                        });
                      },
                      child: Transform.rotate(
                        angle: item.rotation,
                        child: Transform.scale(
                          scale: item.scale,
                          child: item.widget,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),

          // Üst Araç Çubuğu
          Positioned(
            top: 50,
            right: 20,
            child: Column(
              children: [
                if (!_isDrawing && !_isTextEditing && !_isDragging) ...[ // Çizim veya sürükleme yaparken gizle
                  IconButton(icon: const Icon(Icons.music_note, color: Colors.white, size: 30), tooltip: 'Müzik', onPressed: _addMusic),
                  if (!widget.isVideo)
                    IconButton(
                      icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 30),
                      tooltip: 'Filtre Değiştir',
                      onPressed: () {
                        setState(() {
                          _selectedFilterIndex = (_selectedFilterIndex + 1) % _filters.length;
                        });
                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${_filterNames[_selectedFilterIndex]} Filtresi', textAlign: TextAlign.center),
                            duration: const Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: Colors.black87,
                          ),
                        );
                      },
                    ),
                  IconButton(icon: const Icon(Icons.text_fields, color: Colors.white, size: 30), onPressed: _openTextEditor),
                  IconButton(icon: const Icon(Icons.emoji_emotions_outlined, color: Colors.white, size: 30), onPressed: _addSticker),
                  if (!widget.isVideo)
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.white, size: 30),
                    onPressed: () => setState(() => _isDrawing = !_isDrawing),
                  ),
                  IconButton(
                    icon: const Icon(Icons.layers_clear, color: Colors.white, size: 30),
                    tooltip: 'Tümünü Temizle',
                    onPressed: () {
                      setState(() {
                        _overlayItems.clear(); // Sticker ve Yazıları temizle
                        if (!widget.isVideo) _scribbleNotifier.clear(); // Çizimleri temizle
                      });
                    },
                  ),
                  IconButton(icon: const Icon(Icons.location_on, color: Colors.white, size: 30), tooltip: 'Konum', onPressed: _addLocation),
                ],
              ],
            ),
          ),

          // Alt Paylaş Butonu
          Positioned(
            bottom: 30,
            right: 20,
            child: (_isDrawing || _isTextEditing || _isDragging) ? const SizedBox.shrink() : FloatingActionButton.extended(
              onPressed: _isUploading ? null : _shareStory,
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              label: _isUploading 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                : const Row(children: [
                    Text('Hikayende Paylaş', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), 
                    SizedBox(width: 8),
                    Icon(Icons.send, color: Colors.black, size: 18)
                  ]),
            ),
          ),
          
          // Geri Dön
          Positioned(
            top: 50, left: 20,
            child: (_isDrawing || _isTextEditing || _isDragging) ? const SizedBox.shrink() : IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 32), 
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // 🗑️ Çöp Kutusu (Sürükleme sırasında görünür)
          if (_isDragging)
            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedScale(
                  scale: _isDeleteActive ? 1.5 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _isDeleteActive ? Colors.red : Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete, color: Colors.white, size: 32),
                  ),
                ),
              ),
            ),

          // Çizim Araç Çubuğu
          if (_isDrawing) _buildDrawingToolbar(),
          
          // Metin Editörü
          if (_isTextEditing) _buildTextEditor(),
        ],
      ),
    );
  }

  Widget _buildDrawingToolbar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(12),
        color: Colors.black.withOpacity(0.5),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Kalem Kalınlığı Slider
              Slider(
                value: _strokeWidth,
                min: 2.0,
                max: 20.0,
                activeColor: Colors.white,
                inactiveColor: Colors.grey,
                onChanged: (value) {
                  setState(() => _strokeWidth = value);
                  _scribbleNotifier.setStrokeWidth(value);
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.undo, color: Colors.white),
                    onPressed: () => _scribbleNotifier.undo(),
                  ),
                  // Silgi
                  IconButton(
                    icon: const Icon(Icons.cleaning_services_outlined, color: Colors.white),
                    onPressed: () => _scribbleNotifier.setEraser(),
                  ),
                  _buildColorButton(Colors.white),
                  _buildColorButton(Colors.red),
                  _buildColorButton(Colors.green),
                  _buildColorButton(Colors.blue),
                  _buildColorButton(Colors.yellow),
                  IconButton(
                    icon: const Icon(Icons.check_circle, color: Colors.white, size: 32),
                    onPressed: () => setState(() => _isDrawing = false),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorButton(Color color) {
    return GestureDetector(
      onTap: () => _scribbleNotifier.setColor(color),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
      ),
    );
  }
}

// ✨ iTunes API ile Gerçek Müzik Arama
class _MusicSearchSheet extends StatefulWidget {
  final Function(Map<String, dynamic>, double) onSelected;
  const _MusicSearchSheet({required this.onSelected});

  @override
  State<_MusicSearchSheet> createState() => _MusicSearchSheetState();
}

class _MusicSearchSheetState extends State<_MusicSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  final AudioPlayer _previewPlayer = AudioPlayer();
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  String? _playingUrl;
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _previewPlayer.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchPopular();
  }

  Future<void> _fetchPopular() async {
    await _searchMusic('popüler türkçe', isInit: true);
  }

  Future<void> _searchMusic(String query, {bool isInit = false}) async {
    if (query.isEmpty) {
      if (!isInit) _fetchPopular();
      return;
    }
    setState(() => _isLoading = true);
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&media=music&entity=song&limit=30&country=tr'));
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      final data = json.decode(responseBody);
      final results = data['results'] as List;
      
      if (mounted) {
        setState(() {
          _results = results.map((r) => {
            'title': r['trackName']?.toString() ?? 'Bilinmeyen',
            'artist': r['artistName']?.toString() ?? 'Bilinmeyen',
            'url': r['previewUrl']?.toString() ?? '',
            'cover': r['artworkUrl100']?.toString() ?? '',
          }).where((s) => s['url']!.isNotEmpty).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Çizgi
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          width: 40,
          height: 4,
          decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: TextField(
            controller: _searchController,
            autofocus: false,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Müzik veya sanatçı ara...',
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500),
              prefixIcon: const Icon(Icons.search, color: Colors.white, size: 28),
              filled: true,
              fillColor: const Color(0xFF242424),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            onChanged: (value) {
              if (_debounce?.isActive ?? false) _debounce!.cancel();
              _debounce = Timer(const Duration(milliseconds: 500), () => _searchMusic(value));
            },
          ),
        ),
        if (_searchController.text.isEmpty && !_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Önerilenler', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        if (_isLoading) const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFF1DB954))))
        else Expanded(
          child: ListView.builder(
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final song = _results[index];
              final isPlaying = _playingUrl == song['url'];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(song['cover']!, width: 48, height: 48, fit: BoxFit.cover),
                ),
                title: Text(song['title']!, style: TextStyle(color: isPlaying ? const Color(0xFF1DB954) : Colors.white, fontWeight: FontWeight.w500, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(song['artist']!, style: const TextStyle(color: Colors.grey, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: isPlaying ? const Color(0xFF1DB954) : Colors.white, size: 36),
                  onPressed: () async {
                    if (isPlaying) {
                      await _previewPlayer.pause();
                      setState(() => _playingUrl = null);
                    } else {
                      await _previewPlayer.play(UrlSource(song['url']!));
                      setState(() => _playingUrl = song['url']);
                    }
                  },
                ),
                onTap: () {
                  _previewPlayer.stop();
                  Navigator.pop(context);
                  widget.onSelected(song, 0.0); // Müzik otomatik başlar
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
