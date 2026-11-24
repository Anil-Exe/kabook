import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/data/auth_providers.dart';
import '../../core/theme/app_theme.dart';

/// Splash / Onboarding sayfası
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = ref.watch(isLoggedInProvider);

    // Oturum durumunu kontrol et ve yönlendir
    isLoggedIn.when(
      data: (loggedIn) {
        Future.microtask(() {
          if (loggedIn) {
            context.go('/home');
          } else {
            context.go('/login');
          }
        });
      },
      loading: () {},
      error: (_, __) {
        Future.microtask(() => context.go('/login'));
      },
    );

    return Scaffold(
      body: Stack(
        children: [
          // 1. Arka Plan Gradient
          Container(
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
            ),
          ),
          
          // 2. Dekoratif Arka Plan Elementleri (Modern/VIP hissi için)
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
              ),
            ),
          ),

          // 3. Ana İçerik
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ✨ Logo Alanı (Glassmorphism Efekti)
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.1),
                      border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const CircleAvatar(
                      radius: 40, // 80x80 boyutunu korumak için
                      backgroundColor: Colors.transparent, // Olası beyaz arka planı önlemek için
                      backgroundImage: AssetImage('assets/icon/app_icon.png'),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                
                // Uygulama Adı
                Text(
                  'KaBOOK',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 6.0, // VIP hissi için geniş aralık
                      ),
                ),
                const SizedBox(height: 16),
                
                // Slogan (Kapsül Tasarım)
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      'Kampüsün Sosyal Ağı',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white.withOpacity(0.95),
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 80),
                
                // Loader
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 3,
                ),
              ],
            ),
          ),

          // 4. Alt Bilgi (Versiyon)
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'v1.0.0',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
