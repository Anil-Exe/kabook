// lib/features/auth/presentation/pages/register_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/academic_service.dart';
import '../../../../models/academic_models.dart';
import '../../../../utils/user_role_helper.dart';
import '../../data/auth_providers.dart';

// Provider'lar
final academicServiceProvider = Provider((ref) => AcademicService());

final universitiesProvider = FutureProvider<List<University>>((ref) async {
  return ref.read(academicServiceProvider).getUniversities();
});

final facultiesProvider = FutureProvider.family<List<Faculty>, String>((ref, universityId) async {
  return ref.read(academicServiceProvider).getFaculties(universityId);
});

final departmentsProvider = FutureProvider.family<List<Department>, String>((ref, facultyId) async {
  return ref.read(academicServiceProvider).getDepartments(facultyId);
});

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController(); // 🆕 Kullanıcı adı controller

  University? _selectedUniversity;
  Faculty? _selectedFaculty;
  Department? _selectedDepartment;

  String? _detectedRole;
  bool _isLoading = false;
  String? _errorMessage;

  // Username Check State
  Timer? _debounce;
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameController.dispose();
    _usernameController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _updateRoleFromEmail(String email) {
    final role = UserRoleHelper.getRoleFromEmail(email);
    setState(() {
      _detectedRole = role != null ? UserRoleHelper.roleToString(role) : null;
    });
  }

  void _onUsernameChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    setState(() {
      _isUsernameAvailable = null;
      _isCheckingUsername = false;
    });

    if (value.trim().length < 3) return;

    setState(() => _isCheckingUsername = true);

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final isAvailable = await ref.read(authServiceProvider).checkUsernameAvailability(value.trim());
        if (mounted) {
          setState(() {
            _isUsernameAvailable = isAvailable;
            _isCheckingUsername = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isCheckingUsername = false);
      }
    });
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedUniversity == null || _selectedFaculty == null || _selectedDepartment == null) {
      setState(() {
        _errorMessage = 'Lütfen üniversite, fakülte/yüksekokul ve bölüm seçin.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);

      await authService.registerWithEmailPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _fullNameController.text.trim(),
        username: _usernameController.text.trim(), // 🆕 Parametre gönderiliyor
        university: _selectedUniversity!.name,
        faculty: _selectedFaculty!.name,
        department: _selectedDepartment!.name,
      );

      // Oturum durumunu yenile
      ref.invalidate(isLoggedInProvider);
      ref.invalidate(currentUserProvider);

      if (mounted) {
        context.go('/home'); // Başarılı kayıt sonrası yönlendirme
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
    final universitiesAsync = ref.watch(universitiesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kayıt Ol'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Ad Soyad
                  TextFormField(
                    controller: _fullNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Ad Soyad',
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Ad soyad zorunludur';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // 🆕 Kullanıcı Adı Alanı
                  TextFormField(
                    controller: _usernameController,
                    onChanged: _onUsernameChanged,
                    decoration: InputDecoration(
                      labelText: 'Kullanıcı Adı',
                      prefixIcon: const Icon(Icons.alternate_email),
                      hintText: 'kullaniciadi',
                      suffixIcon: _isCheckingUsername
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : (_isUsernameAvailable != null
                              ? Icon(
                                  _isUsernameAvailable! ? Icons.check_circle : Icons.error,
                                  color: _isUsernameAvailable! ? Colors.green : Colors.red,
                                )
                              : null),
                      helperText: _isUsernameAvailable == true ? 'Bu kullanıcı adı müsait' : null,
                      helperStyle: const TextStyle(color: Colors.green),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Kullanıcı adı zorunludur';
                      }
                      if (value.length < 3) {
                        return 'En az 3 karakter olmalı';
                      }
                      if (!RegExp(r'^[a-zA-Z0-9_.]+$').hasMatch(value)) {
                        return 'Sadece harf, rakam, nokta ve alt çizgi kullanılabilir';
                      }
                      if (_isUsernameAvailable == false) {
                        return 'Bu kullanıcı adı kullanımda';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // E-posta
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Kurumsal E-posta',
                      prefixIcon: Icon(Icons.email),
                      hintText: 'örnek@ogr.kastamonu.edu.tr',
                    ),
                    onChanged: _updateRoleFromEmail,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'E-posta zorunludur';
                      }
                      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                        return 'Geçerli bir e-posta girin';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),

                  // Rol Göstergesi
                  if (_detectedRole != null)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.badge, color: Colors.green[700]),
                          const SizedBox(width: 12),
                          Text(
                            'Tespit Edilen Rol: $_detectedRole',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[800],
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_emailController.text.isNotEmpty)
                    const Text(
                      'Uyarı: Sadece Kastamonu Üniversitesi kurumsal e-postaları kabul edilir.',
                      style: TextStyle(color: Colors.orange, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),

                  const SizedBox(height: 16),

                  // Şifre
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Şifre',
                      prefixIcon: Icon(Icons.lock),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Şifre zorunludur';
                      if (value.length < 6) return 'Şifre en az 6 karakter olmalı';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Şifre Tekrar
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Şifre Tekrar',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (value) {
                      if (value != _passwordController.text) return 'Şifreler eşleşmiyor';
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // Üniversite Dropdown
                  universitiesAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (err, stack) => Text('Hata: $err', style: const TextStyle(color: Colors.red)),
                    data: (universities) {
                      if (universities.isEmpty) {
                        return const Text('Hiç üniversite bulunamadı.');
                      }
                      return DropdownButtonFormField<University>(
                        value: _selectedUniversity,
                        decoration: const InputDecoration(
                          labelText: 'Üniversite',
                          prefixIcon: Icon(Icons.school),
                        ),
                        hint: const Text('Üniversite seçin'),
                        items: universities
                            .map((uni) => DropdownMenuItem(
                                  value: uni,
                                  child: Text(uni.name),
                                ))
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedUniversity = value;
                            _selectedFaculty = null;
                            _selectedDepartment = null;
                          });
                        },
                        validator: (value) => value == null ? 'Üniversite seçmelisiniz' : null,
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Fakülte / Yüksekokul Dropdown
                  if (_selectedUniversity != null)
                    Consumer(
                      builder: (context, ref, child) {
                        final facultiesAsync = ref.watch(facultiesProvider(_selectedUniversity!.id));
                        return facultiesAsync.when(
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (err, stack) => Text('Hata: $err', style: const TextStyle(color: Colors.red)),
                          data: (faculties) {
                            if (faculties.isEmpty) {
                              return const Text('Bu üniversiteye ait birim bulunamadı.');
                            }
                            return DropdownButtonFormField<Faculty>(
                              value: _selectedFaculty,
                              decoration: const InputDecoration(
                                labelText: 'Fakülte / Yüksekokul',
                                prefixIcon: Icon(Icons.account_balance),
                              ),
                              hint: const Text('Birim seçin'),
                              items: faculties
                                  .map((fac) => DropdownMenuItem(
                                        value: fac,
                                        child: Text(fac.name),
                                      ))
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedFaculty = value;
                                  _selectedDepartment = null;
                                });
                              },
                              validator: (value) => value == null ? 'Birim seçmelisiniz' : null,
                            );
                          },
                        );
                      },
                    ),

                  const SizedBox(height: 16),

                  // Bölüm Dropdown
                  if (_selectedFaculty != null)
                    Consumer(
                      builder: (context, ref, child) {
                        final departmentsAsync = ref.watch(departmentsProvider(_selectedFaculty!.id));
                        return departmentsAsync.when(
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (err, stack) => Text('Hata: $err', style: const TextStyle(color: Colors.red)),
                          data: (departments) {
                            if (departments.isEmpty) {
                              return const Text('Bu birime ait bölüm bulunamadı.');
                            }
                            return DropdownButtonFormField<Department>(
                              value: _selectedDepartment,
                              decoration: const InputDecoration(
                                labelText: 'Bölüm / Program',
                                prefixIcon: Icon(Icons.menu_book),
                              ),
                              hint: const Text('Bölüm seçin'),
                              items: departments
                                  .map((dept) => DropdownMenuItem(
                                        value: dept,
                                        child: Text(dept.name),
                                      ))
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedDepartment = value;
                                });
                              },
                              validator: (value) => value == null ? 'Bölüm seçmelisiniz' : null,
                            );
                          },
                        );
                      },
                    ),

                  const SizedBox(height: 24),

                  // Hata Mesajı
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).colorScheme.error),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 15),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Kayıt Ol Butonu
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleRegister,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Kayıt Ol', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),

                  const SizedBox(height: 16),

                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Zaten hesabınız var mı? Giriş yapın'),
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