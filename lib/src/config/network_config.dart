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

  const NetworkConfig({
    required this.baseUrl,
    this.connectTimeout = const Duration(milliseconds: 30000),
    this.receiveTimeout = const Duration(milliseconds: 30000),
    this.defaultHeaders,
    this.allowBadCertificate = false,
    this.onUnauthorized,
  });
}
