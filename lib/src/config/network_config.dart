import 'dart:async';

import 'package:dio/dio.dart';

import '../error/exceptions.dart';

// ============================================================================
// TYPEDEFS
// ============================================================================

/// Callback invoked when the server returns HTTP 401 Unauthorized.
typedef OnUnauthorizedCallback = void Function();

/// The structured result returned by a consumer-supplied [ErrorBodyParser].
///
/// Return `null` from the parser to signal "I don't recognise this format"
/// and fall back to the built-in extraction logic.
typedef ErrorBodyParserResult = ({
  String? message,
  String? apiErrorCode,
  List<ValidationError> validationErrors,
});

/// A callback that receives the raw error-response body and HTTP status code
/// and returns structured error data, or `null` to fall back to built-in
/// parsing.
///
/// The callback may be synchronous or asynchronous.
typedef ErrorBodyParser = FutureOr<ErrorBodyParserResult?> Function(
  dynamic body,
  int statusCode,
);

/// A callback that refreshes the access token and returns the new Bearer
/// token string, or `null` to signal failure (which triggers [OnUnauthorizedCallback]).
typedef TokenRefreshCallback = Future<String?> Function();

/// A predicate that identifies whether the given [url] is the token-refresh
/// endpoint, preventing infinite refresh loops.
typedef RefreshEndpointPredicate = bool Function(String url);

/// A hook invoked for every outgoing request.
///
/// Receives the full [RequestOptions] and returns (optionally modified)
/// options used for the actual network call. Multiple hooks are applied in
/// registration order.
typedef RequestHook = FutureOr<RequestOptions> Function(RequestOptions options);

/// A hook invoked for every successful (2xx) response.
///
/// Receives the [Response] and returns an (optionally transformed) response.
/// Multiple hooks are applied in registration order.
typedef ResponseHook = FutureOr<Response<dynamic>> Function(
    Response<dynamic> response);

// ============================================================================
// NETWORK CONFIG
// ============================================================================

/// Configuration for [AppSmartNetworkService] initialization.
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

  /// Called when the server responds with HTTP 401 and token refresh either
  /// is not configured or has failed.
  final OnUnauthorizedCallback? onUnauthorized;

  // ── v1.1.0 additions ──────────────────────────────────────────────────────

  /// Custom parser for error response bodies (US1).
  ///
  /// When provided, called for every 4xx/5xx response with a body. Return
  /// `null` to fall back to built-in extraction.
  final ErrorBodyParser? errorBodyParser;

  /// Callback that fetches a new access token on 401 (US2).
  ///
  /// Return the new Bearer token string on success, or `null` to signal
  /// failure (which triggers [onUnauthorized]).
  final TokenRefreshCallback? tokenRefresher;

  /// Identifies the token-refresh endpoint to prevent infinite loops (US2).
  ///
  /// Required when [tokenRefresher] is provided.
  final RefreshEndpointPredicate? refreshEndpointPredicate;

  /// Ordered pipeline of hooks applied to every outgoing request (US3).
  final List<RequestHook> requestHooks;

  /// Ordered pipeline of hooks applied to every successful (2xx) response (US3).
  final List<ResponseHook> responseHooks;

  const NetworkConfig({
    required this.baseUrl,
    this.connectTimeout = const Duration(milliseconds: 30000),
    this.receiveTimeout = const Duration(milliseconds: 30000),
    this.defaultHeaders,
    this.allowBadCertificate = false,
    this.onUnauthorized,
    // v1.1.0 optional fields:
    this.errorBodyParser,
    this.tokenRefresher,
    this.refreshEndpointPredicate,
    this.requestHooks = const [],
    this.responseHooks = const [],
  });
}
