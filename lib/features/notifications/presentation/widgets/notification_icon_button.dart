import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/notification_providers.dart';
import '../pages/notifications_page.dart';

class NotificationIconButton extends ConsumerWidget {
  const NotificationIconButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    
    Color iconColor;
    if (unreadCount > 0) {
      // Okunmamış varsa ikon aktif renk (Dikkat çekici)
      iconColor = AppColors.brandGreen; 
    } else {
      // Hepsi okunduysa veya yoksa normal gri
      iconColor = Colors.grey; 
    }

    return Stack(
      children: [
        IconButton(
          icon: Icon(Icons.notifications, color: iconColor),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsPage()),
            );
          },
        ),
        if (unreadCount > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              child: Text(
                '$unreadCount',
                style: const TextStyle(color: Colors.white, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}