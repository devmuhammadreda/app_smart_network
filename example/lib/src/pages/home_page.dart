import 'package:app_smart_network/app_smart_network.dart';
import 'package:flutter/material.dart';

import '../datasources/posts_datasource.dart';
import '../models/post_model.dart';

// ============================================================================
// HOME PAGE
// ============================================================================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _datasource = PostsDatasource();

  List<PostModel> _posts = [];
  bool _loading = false;
  String _locale = 'en';

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  // ── Data operations ───────────────────────────────────────────────────────

  Future<void> _loadPosts() async {
    setState(() => _loading = true);
    try {
      final posts = await _datasource.fetchPosts();
      setState(() => _posts = posts);
    } on ApiException catch (e) {
      _showError(e.message);
    } finally {
      setState(() => _loading = false);
    }
  }

  /// Deliberately fetches post id=99999 to trigger a 404.
  Future<void> _triggerError() async {
    try {
      await _datasource.fetchPost(99999);
    } on ApiException catch (e) {
      // ③ e.message is already in the selected locale.
      _showError(
        '${e.errorCategory}\n${e.message}',
        title: 'Error demo (status ${e.statusCode})',
      );
    }
  }

  Future<void> _createPost() async {
    try {
      final post = await _datasource.createPost(
        title: 'New post from example app',
        body: 'Created via app_smart_network package.',
      );
      if (!mounted) return;
      _showSnack('✓ Created: "${post.title}" (id=${post.id})');
    } on ApiException catch (e) {
      _showError(e.message);
    }
  }

  // ④ Switching locale updates both the HTTP header and error messages.
  void _toggleLocale() {
    final next = _locale == 'en' ? 'ar' : 'en';
    _datasource.setLocale(next);
    setState(() => _locale = next);
    _showSnack('Locale → $_locale');
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  void _showError(String message, {String? title}) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title ?? 'Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('app_smart_network example'),
        actions: [
          // Locale toggle
          TextButton.icon(
            onPressed: _toggleLocale,
            icon: const Icon(Icons.language, color: Colors.white),
            label: Text(
              _locale.toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          // Error demo
          IconButton(
            tooltip: 'Trigger 404 error',
            icon: const Icon(Icons.bug_report),
            onPressed: _triggerError,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadPosts,
              child: ListView.separated(
                itemCount: _posts.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final post = _posts[i];
                  return ListTile(
                    leading: CircleAvatar(child: Text('${post.id}')),
                    title: Text(
                      post.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      post.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createPost,
        icon: const Icon(Icons.add),
        label: const Text('Create post'),
      ),
    );
  }
}
