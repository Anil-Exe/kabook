import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../layout/search_service.dart';
import '../../features/post/presentation/widgets/post_card.dart';
import '../../models/post_model.dart';
import '../../services/image_upload_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  
  // Arama sonuçları state'i
  List<dynamic> _userResults = [];
  List<dynamic> _postResults = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (query.isEmpty) {
        setState(() {
          _userResults = [];
          _postResults = [];
        });
        return;
      }

      setState(() => _isLoading = true);
      
      final searchService = ref.read(searchServiceProvider);
      
      try {
        final users = await searchService.searchUsers(query);
        final posts = await searchService.searchPosts(query);
        
        if (mounted) {
          setState(() {
            _userResults = users;
            _postResults = posts;
            _isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _isLoading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Kullanıcı veya gönderi ara...',
            border: InputBorder.none,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Kullanıcılar'),
            Tab(text: 'Gönderiler'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildUserList(),
                _buildPostList(),
              ],
            ),
    );
  }

  Widget _buildUserList() {
    if (_userResults.isEmpty) {
      return const Center(child: Text('Kullanıcı bulunamadı'));
    }
    return ListView.builder(
      itemCount: _userResults.length,
      itemBuilder: (context, index) {
        final doc = _userResults[index];
        final data = doc.data;
        final photoId = data['photoId'] ?? data['profileImageUrl'];
        
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: photoId != null 
                ? CachedNetworkImageProvider(MediaService.getFileUrl(photoId))
                : null,
            child: photoId == null ? const Icon(Icons.person) : null,
          ),
          title: Text(data['displayName'] ?? 'İsimsiz'),
          subtitle: Text('@${data['username'] ?? ''}'),
          onTap: () => context.push('/profile/${data['userId']}'),
        );
      },
    );
  }

  Widget _buildPostList() {
    if (_postResults.isEmpty) {
      return const Center(child: Text('Gönderi bulunamadı'));
    }
    return ListView.builder(
      itemCount: _postResults.length,
      itemBuilder: (context, index) {
        final doc = _postResults[index];
        return PostCard(post: Post.fromMap(doc.toMap()));
      },
    );
  }
}