import 'dart:typed_data';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../core/config/appwrite_config.dart';

class MediaService {
  /// 🌍 Web + Mobile uyumlu InputFile üretir
  /// XFile alır, platforma göre en performanslı yöntemi seçer.
  static Future<InputFile> createInputFile(XFile file) async {
    if (kIsWeb) {
      // 🌐 Web: Bytes okumak zorundayız
      final bytes = await file.readAsBytes();
      return InputFile.fromBytes(
        bytes: bytes,
        filename: file.name,
      );
    } else {
      // 📱 Mobile: Path kullanmak daha performanslıdır (Stream upload)
      return InputFile.fromPath(
        path: file.path,
        filename: file.name,
      );
    }
  }

  /// 📂 PlatformFile (FilePicker) -> InputFile dönüşümü
  static Future<InputFile> createInputFileFromPlatformFile(PlatformFile file) async {
    if (kIsWeb) {
      return InputFile.fromBytes(
        bytes: file.bytes!,
        filename: file.name,
      );
    } else {
      return InputFile.fromPath(
        path: file.path!,
        filename: file.name,
      );
    }
  }

  /// 🔗 File ID'den URL üretir (Client-side generation)
  /// Veritabanında URL saklanmaz, sadece ID saklanır.
  static String getFileUrl(String fileId) {
    return '${AppwriteConfig.endpoint}/storage/buckets/${AppwriteConfig.storageBucketId}/files/$fileId/view?project=${AppwriteConfig.projectId}';
  }
}
