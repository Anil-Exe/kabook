import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appwrite/models.dart' as models;
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/appwrite_service.dart';
import '../../features/profile/data/theme_provider.dart';
import 'search_service.dart';

final searchServiceProvider = Provider<SearchService>((ref) {
  return SearchService(AppwriteService.client);
});

// Arama metnini tutan state
final searchQueryProvider = StateProvider<String>((ref) => '');

// Kullanıcı arama sonuçları
final searchUsersProvider = FutureProvider.autoDispose<List<models.Document>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  // En az 2 karakter girilince aramaya başla
  if (query.isEmpty || query.length < 2) return []; 
  
  return ref.watch(searchServiceProvider).searchUsers(query);
});

// Post arama sonuçları
final searchPostsProvider = FutureProvider.autoDispose<List<models.Document>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty || query.length < 2) return [];
  
  return ref.watch(searchServiceProvider).searchPosts(query);
});

/// Son aramaları yöneten Notifier
class RecentSearchesNotifier extends StateNotifier<List<String>> {
  final SharedPreferences prefs;
  static const _key = 'recent_searches';

  RecentSearchesNotifier(this.prefs) : super(prefs.getStringList(_key) ?? []);

  void add(String query) {
    if (query.trim().isEmpty) return;
    final newState = [...state];
    // Varsa çıkar (en başa eklemek için)
    newState.remove(query);
    // En başa ekle
    newState.insert(0, query);
    // Maksimum 10 kayıt tut
    if (newState.length > 10) {
      newState.removeLast();
    }
    state = newState;
    prefs.setStringList(_key, newState);
  }

  void remove(String query) {
    final newState = [...state];
    newState.remove(query);
    state = newState;
    prefs.setStringList(_key, newState);
  }

  void clear() {
    state = [];
    prefs.remove(_key);
  }
}

final recentSearchesProvider = StateNotifierProvider<RecentSearchesNotifier, List<String>>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return RecentSearchesNotifier(prefs);
});