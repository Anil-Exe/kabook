import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../../features/post/data/providers/post_providers.dart';
import '../../features/post/presentation/widgets/post_card.dart';

/// Yardım sayfası
class HelpPage extends ConsumerStatefulWidget {
  const HelpPage({super.key});

  @override
  ConsumerState<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends ConsumerState<HelpPage> {
  final List<String> _categories = ['Tümü', 'İş', 'Konaklama', 'Sosyal', 'Ulaşım', 'Ders'];
  String _selectedCategory = 'Tümü';

  @override
  Widget build(BuildContext context) {
    // Tüm postları çekiyoruz, client-side filtreleme yapacağız
    final postsAsync = ref.watch(postsProvider);

    // Scaffold ve AppBar yok, MainLayout yönetiyor
    return Column(
      children: [
        // 🔹 ÜST FİLTRELER
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 0, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.1))),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _categories.map((category) {
                final isSelected = _selectedCategory == category;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(category),
                    selected: isSelected,
                    onSelected: (bool selected) {
                      if (selected) {
                        setState(() {
                          _selectedCategory = category;
                        });
                      }
                    },
                    selectedColor: AppColors.primaryGreen,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    backgroundColor: Theme.of(context).cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isSelected ? Colors.transparent : Colors.grey.withOpacity(0.2),
                      ),
                    ),
                    showCheckmark: false,
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // 🔹 İÇERİK LİSTESİ
        Expanded(
          child: postsAsync.when(
            data: (posts) {
              // 🔍 FİLTRELEME MANTIĞI
              final filteredPosts = posts.where((post) {
                final content = post.content.toLowerCase();
                // 1. İçerikte #help veya #yardım geçiyor mu?
                final isHelpPost = content.contains('#help') || content.contains('#yardım');
                if (!isHelpPost) return false;

                // 2. Kategori filtresi
                if (_selectedCategory == 'Tümü') return true;
                return content.contains('#${_selectedCategory.toLowerCase()}');
              }).toList();

              if (filteredPosts.isEmpty) {
                return _buildEmptyState();
              }

              return ListView.builder(
                padding: const EdgeInsets.only(top: 8, bottom: 100),
                itemCount: filteredPosts.length,
                itemBuilder: (context, index) {
                  return PostCard(post: filteredPosts[index]);
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Hata: $e')),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            '$_selectedCategory kategorisinde\nhenüz yardım ilanı yok.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
