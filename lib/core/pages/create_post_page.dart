import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../../features/auth/data/auth_providers.dart';
import '../../features/post/data/providers/post_providers.dart';

class CreatePostPage extends ConsumerStatefulWidget {
  const CreatePostPage({super.key});

  @override
  ConsumerState<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends ConsumerState<CreatePostPage> {
  final _contentController = TextEditingController();
  bool _isLoading = false;
  
  // Gönderi Tipi: 0 = Genel, 1 = Yardım
  int _postType = 0;
  
  // Yardım Kategorileri
  final List<String> _helpCategories = ['İş', 'Konaklama', 'Sosyal', 'Ulaşım', 'Ders'];
  String _selectedHelpCategory = 'İş';

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final currentUser = ref.read(currentUserProvider).value;
      if (currentUser == null) throw Exception('Oturum bulunamadı');

      // Etiketleri hazırla
      List<String> tags = [];
      
      if (_postType == 1) {
        // Yardım gönderisi ise etiketleri ekle
        tags.add('help'); // Genel yardım etiketi
        tags.add(_selectedHelpCategory); // Kategori etiketi
      }

      // Servisi çağır
      await ref.read(postServiceProvider).createPost(
        userId: currentUser.$id,
        content: content,
        tags: tags,
      );

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gönderi paylaşıldı!')),
        );
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gönderi Oluştur'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24),
              ),
              child: _isLoading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Paylaş'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 🔹 GÖNDERİ TİPİ SEÇİMİ
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.1))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildTypeButton(0, 'Genel', Icons.public),
                    const SizedBox(width: 12),
                    _buildTypeButton(1, 'Yardım İste', Icons.support_agent),
                  ],
                ),
                
                // Yardım seçiliyse kategori göster
                if (_postType == 1) ...[
                  const SizedBox(height: 16),
                  const Text('Kategori Seçin:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _helpCategories.map((cat) {
                        final isSelected = _selectedHelpCategory == cat;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(cat),
                            selected: isSelected,
                            onSelected: (val) {
                              if (val) setState(() => _selectedHelpCategory = cat);
                            },
                            selectedColor: AppColors.primaryGreen,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 🔹 İÇERİK ALANI
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _contentController,
                maxLines: null,
                decoration: InputDecoration(
                  hintText: _postType == 0 
                      ? 'Neler oluyor?' 
                      : 'Hangi konuda yardıma ihtiyacın var? Detayları buraya yaz...',
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeButton(int type, String label, IconData icon) {
    final isSelected = _postType == type;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _postType = type),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryGreen.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primaryGreen : Colors.grey.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: isSelected ? AppColors.primaryGreen : Colors.grey),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppColors.primaryGreen : Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}