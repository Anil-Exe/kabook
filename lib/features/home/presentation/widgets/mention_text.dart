import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:appwrite/appwrite.dart';
import '../../../../core/config/appwrite_config.dart';
import '../../../../services/appwrite_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../post/presentation/pages/hashtag_page.dart';

class MentionText extends ConsumerWidget {
  final String text;
  final TextStyle? style;
  final Color mentionColor;

  const MentionText({
    super.key,
    required this.text,
    this.style,
    this.mentionColor = AppColors.primaryGreen,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<TextSpan> spans = [];
    
    // Regex: Hem @mention hem de #hashtag yakalar
    // Örnek: @ahmet, #flutter, #yazilim-dunyasi
    // 🟢 GÜNCELLEME: Türkçe karakter desteği eklendi (çÇğĞıİöÖşŞüÜ)
    final RegExp regex = RegExp(r"([@#][a-zA-Z0-9_.\-çÇğĞıİöÖşŞüÜ]+)");
    
    text.splitMapJoin(
      regex,
      onMatch: (Match match) {
        final String matchText = match[0]!;
        final String content = matchText.substring(1); // Remove @ or #

        spans.add(
          TextSpan(
            text: matchText,
            style: (style ?? const TextStyle()).copyWith(
              color: mentionColor,
              fontWeight: FontWeight.bold,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () async {
                if (matchText.startsWith('@')) {
                  // --- MENTION (@) ---
                  try {
                    final databases = AppwriteService.databases;
                    final result = await databases.listDocuments(
                      databaseId: AppwriteConfig.databaseId,
                      collectionId: AppwriteConfig.usersCollectionId,
                      queries: [
                        Query.equal('username', content),
                        Query.limit(1),
                      ],
                    );

                    if (result.documents.isNotEmpty && context.mounted) {
                      final userId = result.documents.first.data['userId'];
                      context.push('/profile/$userId');
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Kullanıcı bulunamadı')),
                        );
                      }
                    }
                  } catch (e) {
                    // Hata yönetimi
                  }
                } else if (matchText.startsWith('#')) {
                  // --- HASHTAG (#) ---
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HashtagPage(tag: content),
                    ),
                  );
                }
              },
          ),
        );
        return matchText;
      },
      onNonMatch: (String nonMatch) {
        spans.add(TextSpan(text: nonMatch, style: style));
        return nonMatch;
      },
    );

    return RichText(
      text: TextSpan(
        style: style ?? DefaultTextStyle.of(context).style,
        children: spans,
      ),
    );
  }
}
