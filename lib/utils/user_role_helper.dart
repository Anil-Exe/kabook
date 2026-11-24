// TODO Implement this library.// lib/utils/user_role_helper.dart

/// Kullanıcı rolleri
enum UserRole {
  ogrenci,
  akademik,
  idari,
}

/// E-posta adresine göre kullanıcı rolünü tespit eder
class UserRoleHelper {
  /// Desteklenen mail uzantıları (tek yerden değiştirilebilir)
  static const String _studentDomain = '@ogr.kastamonu.edu.tr';
  static const String _staffDomain = '@kastamonu.edu.tr';

  /// Verilen e-postadan rolü döndürür, uygun değilse null
  static UserRole? getRoleFromEmail(String email) {
    if (email.isEmpty) return null;

    final trimmed = email.toLowerCase().trim();

    if (trimmed.endsWith(_studentDomain)) {
      return UserRole.ogrenci;
    }

    if (trimmed.endsWith(_staffDomain)) {
      return UserRole.akademik; // şimdilik idari personeli de akademik olarak kabul ediyoruz
    }

    return null;
  }

  /// Rolü kullanıcıya gösterilecek Türkçe metne çevirir
  static String roleToString(UserRole role) {
    switch (role) {
      case UserRole.ogrenci:
        return 'Öğrenci';
      case UserRole.akademik:
        return 'Akademik';
      case UserRole.idari:
        return 'İdari';
    }
  }

  /// Opsiyonel: Rolü kısa kod olarak döndürür (ileride filtreleme için faydalı olabilir)
  static String roleToShortString(UserRole role) {
    switch (role) {
      case UserRole.ogrenci:
        return 'ogr';
      case UserRole.akademik:
        return 'akd';
      case UserRole.idari:
        return 'idr';
    }
  }

  /// Hata mesajı (AuthService'te kullanabilirsin)
  static String getInvalidEmailMessage() {
    return 'Sadece Kastamonu Üniversitesi kurumsal e-posta adresleri kabul edilmektedir:\n'
        '• Öğrenciler: ...@ogr.kastamonu.edu.tr\n'
        '• Akademik/İdari Personel: ...@kastamonu.edu.tr';
  }
}