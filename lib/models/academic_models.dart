// lib/models/academic_models.dart

class University {
  final String id;
  final String name;
  final String shortName;
  final String domainStudent;
  final String domainStaff;

  University({
    required this.id,
    required this.name,
    required this.shortName,
    required this.domainStudent,
    required this.domainStaff,
  });

  factory University.fromMap(Map<String, dynamic> map) {
    return University(
      id: map['\$id'] as String,  // <-- BURASI DÜZELTİLDİ: \$id
      name: map['name'] as String,
      shortName: map['shortName'] as String? ?? '',
      domainStudent: map['domainStudent'] as String,
      domainStaff: map['domainStaff'] as String,
    );
  }
}

class Faculty {
  final String id;
  final String universityId;
  final String name;
  final String? type;

  Faculty({
    required this.id,
    required this.universityId,
    required this.name,
    this.type,
  });

  factory Faculty.fromMap(Map<String, dynamic> map) {
    return Faculty(
      id: map['\$id'] as String,  // <-- BURASI DÜZELTİLDİ
      universityId: map['universityId'] as String,
      name: map['name'] as String,
      type: map['type'] as String?,
    );
  }
}

class Department {
  final String id;
  final String facultyId;
  final String name;

  Department({
    required this.id,
    required this.facultyId,
    required this.name,
  });

  factory Department.fromMap(Map<String, dynamic> map) {
    return Department(
      id: map['\$id'] as String,  // <-- BURASI DÜZELTİLDİ
      facultyId: map['facultyId'] as String,
      name: map['name'] as String,
    );
  }
}