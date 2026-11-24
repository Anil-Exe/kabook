// lib/services/academic_service.dart

import 'package:appwrite/appwrite.dart';
import '../models/academic_models.dart';
import 'appwrite_service.dart'; // senin mevcut Appwrite singleton'ın

class AcademicService {
  final Databases _databases = AppwriteService.databases;
  static const String databaseId = 'demo_databaseId';

  Future<List<University>> getUniversities() async {
    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: 'universities',
      );
      return result.documents.map((doc) => University.fromMap(doc.data)).toList();
    } catch (e) {
      throw Exception('Üniversiteler yüklenemedi: $e');
    }
  }

  Future<List<Faculty>> getFaculties(String universityId) async {
    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: 'faculties',
        queries: [Query.equal('universityId', universityId)],
      );
      return result.documents.map((doc) => Faculty.fromMap(doc.data)).toList();
    } catch (e) {
      throw Exception('Fakülteler/Yüksekokullar yüklenemedi: $e');
    }
  }

  Future<List<Department>> getDepartments(String facultyId) async {
    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: 'departments',
        queries: [Query.equal('facultyId', facultyId)],
      );
      return result.documents.map((doc) => Department.fromMap(doc.data)).toList();
    } catch (e) {
      throw Exception('Bölümler yüklenemedi: $e');
    }
  }
}