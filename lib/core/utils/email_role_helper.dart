enum UserRole { akademik, idari, ogrenci }

class EmailRoleHelper {
  static UserRole? getRoleFromEmail(String email) {
    email = email.toLowerCase().trim();

    if (email.endsWith('@ogr.kastamonu.edu.tr')) {
      return UserRole.ogrenci;
    }

    if (email.endsWith('@kastamonu.edu.tr')) {
      return UserRole.akademik; // idari ayrımı sonra
    }

    return null;
  }

  static String roleToString(UserRole role) {
    switch (role) {
      case UserRole.akademik:
        return 'Akademik';
      case UserRole.idari:
        return 'İdari';
      case UserRole.ogrenci:
        return 'Öğrenci';
    }
  }
}
