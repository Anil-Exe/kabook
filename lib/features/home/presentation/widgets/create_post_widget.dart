import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabook_app/models/post_model.dart';
import 'package:kabook_app/services/post_service.dart';
import '../../../post/data/providers/post_providers.dart';
import '../../../auth/data/auth_providers.dart';

/// Gönderi oluşturma widget'ı
class CreatePostWidget extends ConsumerStatefulWidget {
  const CreatePostWidget({super.key});

  @override
  ConsumerState<CreatePostWidget> createState() => _CreatePostWidgetState();
}

class _CreatePostWidgetState extends ConsumerState<CreatePostWidget> {
  final _textController = TextEditingController();
  bool _isPosting = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _createPost() async {
    if (_textController.text.trim().isEmpty) {
      return;
    }

    final currentUser = await ref.read(currentUserProvider.future);
    if (currentUser == null) return;

    setState(() {
      _isPosting = true;
    });

    try {
      final newPost = Post(
        id: '', // Appwrite will generate this
        userId: currentUser.$id,
        content: _textController.text.trim(),
        createdAt: DateTime.now(),
      );
      await ref.read(postServiceProvider).createPost(post: newPost);

      _textController.clear();
      ref.invalidate(postsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gönderi paylaşıldı')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPosting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(0),
      elevation: 0,
      color: Theme.of(context).colorScheme.surface.withAlpha(50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            TextField(
              controller: _textController,
              maxLines: 4,
              minLines: 2,
              decoration: const InputDecoration(
                hintText: 'Ne düşünüyorsun?',
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: _isPosting ? null : _createPost,
                  child: _isPosting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
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

