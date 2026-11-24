import 'package:appwrite/appwrite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/appwrite_config.dart';

/// =======================================================
/// APPWRITE SERVICE
/// Tüm Appwrite servislerinin tek merkezden yönetimi
/// =======================================================
class AppwriteService {
  AppwriteService._(); // dışarıdan new'lenmesin

  static Client? _client;
  static Account? _account;
  static Databases? _databases;
  static Realtime? _realtime;
  static Storage? _storage;

  /// 🔹 Client oluştur
  static Client _createClient() {
    return Client()
      ..setEndpoint(AppwriteConfig.endpoint)
      ..setProject(AppwriteConfig.projectId);
  }

  /// 🔹 Client
  static Client get client {
    _client ??= _createClient();
    return _client!;
  }

  /// 🔹 Account
  static Account get account {
    _account ??= Account(client);
    return _account!;
  }

  /// 🔹 Databases
  static Databases get databases {
    _databases ??= Databases(client);
    return _databases!;
  }

  /// 🔹 Realtime
  static Realtime get realtime {
    _realtime ??= Realtime(client);
    return _realtime!;
  }

  /// 🔹 Storage
  static Storage get storage {
    _storage ??= Storage(client);
    return _storage!;
  }

  /// 🔹 File Preview URL
  static String getFilePreviewUrl(String fileId) {
    return '${client.endPoint}/storage/buckets/'
        '${AppwriteConfig.storageBucketId}/files/$fileId/preview'
        '?project=${AppwriteConfig.projectId}';
  }

  /// 🔹 File View URL (Audio/Video/Download için)
  static String getFileViewUrl(String fileId) {
    return '${client.endPoint}/storage/buckets/'
        '${AppwriteConfig.storageBucketId}/files/$fileId/view'
        '?project=${AppwriteConfig.projectId}';
  }
}

/// =======================================================
/// RIVERPOD PROVIDER
/// =======================================================
final appwriteServiceProvider = Provider<AppwriteService>((ref) {
  return AppwriteService._();
});
  
