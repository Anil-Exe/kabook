import 'package:flutter/material.dart';

class CustomPopup {
  static Future<void> showSuccess({
    required BuildContext context,
    required String title,
    required String message,
  }) async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: false, // Kullanıcı sadece butona basarak geçmeli
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.6),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.8,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.2),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.elasticOut,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: const Icon(Icons.check_circle_rounded, size: 72, color: Colors.green),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: const TextStyle(fontSize: 15, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Harika', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
    );
  }
}