import 'package:dio/dio.dart';

import 'certificate_pinning_config.dart';
import 'retry_policy.dart';

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
  ///
  /// Cannot be combined with [certificatePinning]; see that field.
  final bool allowBadCertificate;

  /// SSL/TLS certificate pinning, or `null` (the default) for none.
  ///
  /// With `null` the package behaves exactly as it always has: normal chain
  /// validation, no pinning. Supply a [CertificatePinningConfig] to
  /// additionally require the server's certificate to match a known SHA-256
  /// fingerprint before any request is sent.
  ///
  /// ```dart
  /// ApiService.initialize(NetworkConfig(
  ///   baseUrl: 'https://api.example.com',
  ///   certificatePinning: CertificatePinningConfig(
  ///     allowedSHAFingerprints: ['AA:BB:...', 'CC:DD:...'],
  ///   ),
  /// ));
  /// ```
  ///
  /// Setting this together with [allowBadCertificate] throws [ArgumentError]
  /// when the client is built: one disables validation while the other
  /// tightens it, and silently accepting the pair would produce an app that
  /// looks pinned but is not.
  ///
  /// Pinning applies to **every** request this client makes, not to a chosen
  /// set of hosts — point a separate `NetworkConfig` at anything that needs
  /// different pins. Requires Android or iOS; see [CertificatePinningConfig].
  final CertificatePinningConfig? certificatePinning;

  /// Called when the server responds with HTTP 401.
  final OnUnauthorizedCallback? onUnauthorized;

  /// Custom interceptors spliced into the built-in chain.
  ///
  /// They run **before** the retry interceptor, the 401 handler, and the
  /// debug logger:
  ///
  /// - For a 401 (not retried — see [onUnauthorized]) that's the request's
  ///   only real attempt, so `onError` fires exactly once, before
  ///   [onUnauthorized] tears down the session.
  /// - For a retryable failure, each retry restarts the whole chain from the
  ///   top, so `onError` fires once per genuine attempt, each with its own
  ///   distinct exception. Positioned after retry instead, an interceptor
  ///   would see the *same* terminal exception re-forwarded once per retry
  ///   level as `dio_smart_retry` unwinds (N+1 duplicate calls for N
  ///   retries, all reporting the one final failure).
  /// - They precede the debug logger, so any headers they add appear in
  ///   debug logs.
  ///
  /// Interceptors are fixed at initialization; call `ApiService.initialize()`
  /// again with a new config to change them. Pass fresh interceptor instances
  /// when doing so — the package closes the old Dio client but does not
  /// dispose consumer interceptors, so reusing a stateful instance across
  /// re-initialization can carry over stale state.
  final List<Interceptor> interceptors;

  /// App-wide retry behaviour, or `null` to never retry.
  ///
  /// Defaults to [RetryPolicy] — three retries on idempotent methods with a
  /// 1 s / 2 s / 3 s backoff — which is what the package has always done.
  ///
  /// Any single call can override this by passing its own policy:
  ///
  /// ```dart
  /// await api.request(HttpMethod.post, '/pay', retry: RetryPolicy.off);
  /// ```
  ///
  /// [RetryPolicy.delays] and [RetryPolicy.methods] are read from this
  /// app-wide policy only; see [RetryPolicy] for why.
  final RetryPolicy? retry;

  const NetworkConfig({
    required this.baseUrl,
    this.connectTimeout = const Duration(milliseconds: 30000),
    this.receiveTimeout = const Duration(milliseconds: 30000),
    this.defaultHeaders,
    this.allowBadCertificate = false,
    this.certificatePinning,
    this.onUnauthorized,
    this.interceptors = const [],
    this.retry = const RetryPolicy(),
  });
}
