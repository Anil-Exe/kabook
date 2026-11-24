import 'package:appwrite/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import 'post_preview_widget.dart';

class MessageBubble extends ConsumerWidget {
  final Document message;
  final bool isMe;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = message.data;
    final type = data['messageType'] as String? ?? 'text';
    final content = data['content'] as String? ?? '';
    final postId = data['postId'] as String?;
    final createdAt = DateTime.parse(message.$createdAt);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe ? AppColors.primaryGreen : Theme.of(context).cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 📌 Mesaj Tipi Kontrolü
            if (type == 'post' && postId != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Post Önizlemesi
                  PostPreviewWidget(postId: postId),
                  // Eğer ek açıklama varsa (otomatik mesaj dışında) altına ekle
                  if (content.isNotEmpty && content != 'Bir gönderi paylaştı')
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        content,
                        style: TextStyle(
                          color: isMe ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
                          fontSize: 14,
                        ),
                      ),
                    ),
                ],
              )
            else
              Text(
                content,
                style: TextStyle(
                  color: isMe ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
                  fontSize: 16,
                ),
              ),
            
            const SizedBox(height: 4),
            
            // 🕒 Saat
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                DateFormat('HH:mm').format(createdAt),
                style: TextStyle(
                  color: isMe ? Colors.white70 : Colors.grey,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}