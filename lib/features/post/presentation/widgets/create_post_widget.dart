import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabook_app/features/post/data/providers/post_providers.dart';
import 'package:kabook_app/models/post_model.dart';
import 'package:kabook_app/services/post_service.dart';
import '../../../../services/auth_service.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../../utils/custom_popup.dart';

class CreatePostWidget extends ConsumerStatefulWidget {
  const CreatePostWidget({super.key});

  @override
  ConsumerState<CreatePostWidget> createState() => _CreatePostWidgetState();
}

class _CreatePostWidgetState extends ConsumerState<CreatePostWidget> {
  final _controller = TextEditingController();
  final _tagsController = TextEditingController();
  final _imageController = TextEditingController(); // Şimdilik URL girişi
  bool _isLoading = false;

  Future<void> _sharePost() async {
    if (_controller.text.trim().isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final user = await ref.read(currentUserProvider.future);
      if (user == null) return;

      // Etiketleri ayır (virgül veya boşluk ile)
      final tags = _tagsController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

      await ref.read(postServiceProvider).createPost(
        userId: user.$id,
        content: _controller.text.trim(),
        imageUrl: _imageController.text.trim().isNotEmpty ? _imageController.text.trim() : null,
        tags: tags,
      );

      _controller.clear();
      _tagsController.clear();
      _imageController.clear();
      ref.invalidate(postsProvider);

      if (mounted) {
        await CustomPopup.showSuccess(
          context: context,
          title: 'Harika!',
          message: 'Gönderin başarıyla paylaşıldı.',
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _tagsController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primaryGreen = const Color(0xFF1DB954);
    final cream = const Color(0xFFF5F5DC);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            /// ✍️ INPUT
            TextField(
              controller: _controller,
              maxLines: 4,
              minLines: 2,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? cream : Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: 'Ne düşünüyorsun?',
                hintStyle: TextStyle(
                  color: isDark
                      ? cream.withOpacity(0.6)
                      : Colors.grey[600],
                ),
                filled: true,
                fillColor: isDark
                    ? Colors.grey.shade900
                    : Colors.grey.shade100,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 12),

            /// 🏷️ ETİKETLER & RESİM (Basit Inputlar)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagsController,
                    decoration: const InputDecoration(
                      hintText: 'Etiketler (örn: kitap, roman)',
                      prefixIcon: Icon(Icons.tag, size: 18),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _imageController,
                    decoration: const InputDecoration(
                      hintText: 'Resim URL',
                      prefixIcon: Icon(Icons.image, size: 18),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            /// 🚀 PAYLAŞ BUTONU
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: _isLoading ? null : _sharePost,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    foregroundColor: cream,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 0.5,
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFF5F5DC),
                          ),
                        )
                      : const Text('Paylaş'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
