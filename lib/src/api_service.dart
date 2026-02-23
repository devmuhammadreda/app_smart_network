import 'dart:io';

import 'package:dio/dio.dart';

import 'client/http_client.dart';
import 'config/network_config.dart';
import 'i18n/network_locale.dart';
import 'services/download_service.dart';
import 'services/request_service.dart';
import 'services/upload_service.dart';

export 'services/request_service.dart' show HttpMethod;

// ============================================================================
// API SERVICE  –  Main entry point
// ============================================================================

/// Singleton network service.
///
/// **Setup** (call once in `main()` or before first request):
/// ```dart
/// ApiService.initialize(NetworkConfig(
///   baseUrl: 'https://api.example.com',
///   onUnauthorized: () {
///     ApiService.instance.removeAuthToken();
///     // navigate to login
///   },
/// ));
/// ```
///
/// **Usage**:
/// ```dart
/// final response = await ApiService.instance.request<Map<String, dynamic>>(
///   HttpMethod.get,
///   '/users/me',
/// );
/// ```
class ApiService {
  static ApiService? _instance;

  // Stores the locale set at initialize() so removeAppLocale() can restore it.
  static String _defaultLocale = 'en';

  late HttpClient _httpClient;
  late RequestService _requestService;
  late DownloadRequestService _downloadService;
  late UploadRequestService _uploadService;

  // ── Singleton access ──────────────────────────────────────────────────────

  /// Returns the singleton.
  ///
  /// Throws [StateError] if [initialize] has not been called yet.
  static ApiService get instance {
    if (_instance == null) {
      throw StateError(
        'ApiService is not initialized. '
        'Call ApiService.initialize(NetworkConfig(...)) in main() before first use.',
      );
    }
    return _instance!;
  }

  /// Whether [initialize] has already been called.
  static bool get isInitialized => _instance != null;

  /// Initialises (or re-initialises) the singleton with [config].
  ///
  /// Call this once in `main()` before making any requests.
  static void initialize(NetworkConfig config) {
    _instance?.dispose();
    _defaultLocale = config.defaultHeaders?['Accept-Language']
            ?.split(RegExp(r'[-_]'))
            .first
            .toLowerCase() ??
        'en';
    NetworkLocale.setLocale(_defaultLocale);
    _instance = ApiService._create(config);
  }

  ApiService._create(NetworkConfig config) {
    _httpClient = HttpClient(config);
    _requestService = RequestService(_httpClient);
    _downloadService = DownloadRequestService(_httpClient);
    _uploadService = UploadRequestService(_httpClient);
  }

  // ── Dynamic configuration ─────────────────────────────────────────────────

  /// Updates runtime settings without recreating the client.
  void configure({
    String? baseUrl,
    int? connectTimeoutMs,
    int? receiveTimeoutMs,
    Map<String, dynamic>? headers,
  }) {
    if (baseUrl != null) _httpClient.dio.options.baseUrl = baseUrl;
    if (connectTimeoutMs != null) {
      _httpClient.dio.options.connectTimeout =
          Duration(milliseconds: connectTimeoutMs);
    }
    if (receiveTimeoutMs != null) {
      _httpClient.dio.options.receiveTimeout =
          Duration(milliseconds: receiveTimeoutMs);
    }
    if (headers != null) _httpClient.dio.options.headers.addAll(headers);
  }

  // ── Auth helpers ──────────────────────────────────────────────────────────

  void setAuthToken(String token) {
    _httpClient.dio.options.headers['Authorization'] = 'Bearer $token';
  }

  void removeAuthToken() {
    _httpClient.dio.options.headers.remove('Authorization');
  }

  // ── Locale helper ─────────────────────────────────────────────────────────

  /// Sets the `Accept-Language` header **and** updates [NetworkLocale] so
  /// all subsequent error messages are returned in [locale].
  ///
  /// ```dart
  /// ApiService.instance.setAppLocale('ar');
  /// ```
  void setAppLocale(String locale) {
    NetworkLocale.setLocale(locale);
    _httpClient.dio.options.headers['Accept-Language'] = locale;
  }

  void removeAppLocale() {
    _httpClient.dio.options.headers.remove('Accept-Language');
    // Restore to the locale that was active at initialize(), not always 'en'.
    NetworkLocale.setLocale(_defaultLocale);
  }

  // ── Request ───────────────────────────────────────────────────────────────

  Future<Response<T>> request<T>(
    HttpMethod method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    String? baseUrl,
  }) {
    return _requestService.execute<T>(
      method,
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      baseUrl: baseUrl,
    );
  }

  // ── Download ──────────────────────────────────────────────────────────────

  Future<Response> download(
    String urlPath,
    String savePath, {
    ProgressCallback? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    String lengthHeader = Headers.contentLengthHeader,
    Options? options,
    String? baseUrl,
  }) {
    return _downloadService.execute(
      urlPath,
      savePath,
      onReceiveProgress: onReceiveProgress,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
      deleteOnError: deleteOnError,
      lengthHeader: lengthHeader,
      options: options,
      baseUrl: baseUrl,
    );
  }

  // ── Upload ────────────────────────────────────────────────────────────────

  Future<Response<T>> uploadFile<T>(
    String path,
    File file, {
    String fieldName = 'file',
    String? fileName,
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    String? baseUrl,
  }) {
    return _uploadService.execute<T>(
      path,
      file,
      fieldName: fieldName,
      fileName: fileName,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      baseUrl: baseUrl,
    );
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void dispose() {
    _httpClient.dispose();
    _instance = null;
  }
}
