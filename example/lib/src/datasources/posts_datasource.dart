import 'package:app_smart_network/app_smart_network.dart';

import '../models/post_model.dart';

// ============================================================================
// POSTS DATASOURCE  –  shows typical ApiService usage patterns
// ============================================================================

class PostsDatasource {
  // ① Access the singleton directly – no constructor injection needed.
  final AppSmartNetworkService _api = AppSmartNetworkService.instance;

  // ─────────────────────────────────────────────────────────────────────────
  // GET  /posts  – fetch all posts
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns a list of [PostModel].
  ///
  /// Any network or HTTP error is rethrown as an [ApiException] with a
  /// message already translated to the current app locale.
  Future<List<PostModel>> fetchPosts() async {
    final response = await _api.request<List<dynamic>>(
      HttpMethod.get,
      '/posts',
    );

    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(PostModel.fromJson)
        .toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GET  /posts/:id  – fetch a single post (pass a bad id to demo 404)
  // ─────────────────────────────────────────────────────────────────────────

  Future<PostModel> fetchPost(int id) async {
    final response = await _api.request<Map<String, dynamic>>(
      HttpMethod.get,
      '/posts/$id',
    );
    return PostModel.fromJson(response.data!);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // POST  /posts  – create a new post
  // ─────────────────────────────────────────────────────────────────────────

  Future<PostModel> createPost({
    required String title,
    required String body,
  }) async {
    final response = await _api.request<Map<String, dynamic>>(
      HttpMethod.post,
      '/posts',
      data: PostModel(id: 0, userId: 1, title: title, body: body).toJson(),
    );
    return PostModel.fromJson(response.data!);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LOCALE  –  switches the Accept-Language header and error message locale
  // ─────────────────────────────────────────────────────────────────────────

  /// ② Call this whenever the user changes the app language.
  ///    Both the HTTP header and internal error-message locale are updated.
  void setLocale(String locale) => _api.setAppLocale(locale);
}
