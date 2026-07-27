import 'package:dio/dio.dart';

/// Callback invoked when the server returns HTTP 401 Unauthorized.
typedef OnUnauthorizedCallback = void Function();

/// Configuration for [ApiService] initialization.
class NetworkConfig {
  /// Base URL prepended to every request path.
  final String baseUrl;

  /// Timeout for establishing a connection (default 30 s).
  final Duration connectTimeout;

  /// Timeout for receiving the full response (default 30 s).
  final Duration receiveTimeout;

  /// Additional default headers merged on top of [Content-Type / accept].
  final Map<String, String>? defaultHeaders;

  /// Set to `true` to bypass SSL certificate validation.
  /// **Only use in development / debug builds.**
  final bool allowBadCertificate;

  /// Called when the server responds with HTTP 401.
  final OnUnauthorizedCallback? onUnauthorized;

  /// Custom interceptors spliced into the built-in chain.
  ///
  /// They run after the retry interceptor and before the 401 handler and the
  /// debug logger, so they can observe a 401 before [onUnauthorized] fires and
  /// any headers they add appear in debug logs.
  ///
  /// Interceptors are fixed at initialization; call `ApiService.initialize()`
  /// again with a new config to change them.
  final List<Interceptor> interceptors;

  const NetworkConfig({
    required this.baseUrl,
    this.connectTimeout = const Duration(milliseconds: 30000),
    this.receiveTimeout = const Duration(milliseconds: 30000),
    this.defaultHeaders,
    this.allowBadCertificate = false,
    this.onUnauthorized,
    this.interceptors = const [],
  });
}
