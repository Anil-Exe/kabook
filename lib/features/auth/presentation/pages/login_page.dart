import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../services/auth_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/auth_providers.dart';

/// Giriş yap sayfası
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      await authService.login(
        identifier: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // Başarılı giriş - provider'ı yenile
      ref.invalidate(isLoggedInProvider);
      ref.invalidate(currentUserProvider);

      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo
                  Icon(
                    Icons.book,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'KaBOOK',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                  const SizedBox(height: 48),
                  // E-posta alanı
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-posta veya Kullanıcı Adı',
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Lütfen e-posta veya kullanıcı adı girin';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  // Şifre alanı
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Şifre',
                      prefixIcon: Icon(Icons.lock),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Lütfen şifrenizi girin';
                      }
                      if (value.length < 6) {
                        return 'Şifre en az 6 karakter olmalıdır';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  // Hata mesajı
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  // Giriş butonu
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Giriş Yap'),
                  ),
                  const SizedBox(height: 16),
                  // Kayıt ol linki
                  TextButton(
                    onPressed: () => context.go('/register'),
                    child: const Text('Hesabınız yok mu? Kayıt olun'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
