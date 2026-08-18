import 'dart:convert';
import 'dart:developer';
import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter/foundation.dart';
import 'package:http_certificate_pinning/http_certificate_pinning.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../config/certificate_pinning_config.dart';
import '../config/network_config.dart';
import '../config/retry_policy.dart';
import '../interceptors/unauth_interceptor.dart';

// ── Background JSON decoding ───────────────────────────────────────────────

dynamic _parseAndDecode(String response) => jsonDecode(response);
Future<dynamic> _parseJsonInBg(String text) => compute(_parseAndDecode, text);

// ── Default headers ────────────────────────────────────────────────────────

const _defaultHeaders = {
  'Content-Type': 'application/json',
  'accept': 'application/json',
};

// ============================================================================
// HTTP CLIENT
// ============================================================================

class HttpClient {
  late final Dio _dio;

  HttpClient(NetworkConfig config) {
    _dio = Dio();
    _setup(config);
  }

  void _setup(NetworkConfig config) {
    final pinning = _resolvePinning(config);

    _dio.options = BaseOptions(
      baseUrl: config.baseUrl,
      connectTimeout: config.connectTimeout,
      receiveTimeout: config.receiveTimeout,
      headers: {
        ..._defaultHeaders,
        ...?config.defaultHeaders,
      },
      persistentConnection: true,
      maxRedirects: 3,
    );

    // Offload JSON decoding to a background isolate.
    _dio.transformer = BackgroundTransformer()
      ..jsonDecodeCallback = _parseJsonInBg;

    // Order matters: consumer interceptors run first, before retry. For a
    // non-retryable failure (e.g. a 401 — see UnAuthInterceptor below) that's
    // the request's only real attempt, so onError fires exactly once either
    // way. The position matters for *retryable* failures: dio_smart_retry
    // retries by calling dio.fetch() again, which restarts the whole chain
    // from index 0, so consumers positioned before retry see one onError per
    // genuine attempt, each with its own distinct DioException. Positioned
    // after retry, they'd instead see the *same* terminal DioException
    // object re-forwarded once per unwind level as each nested fetch()
    // rejects (N+1 calls for N retries, all reporting the one final failure)
    // — a misleading duplicate signal, not a legitimate one. Consumer
    // interceptors still precede UnAuthInterceptor, so they can handle a 401
    // before onUnauthorized tears down the session, and precede the logger,
    // so debug output reflects the final request after all mutations.
    // dio.fetch() restarts the chain from index 0 on every attempt
    // regardless of interceptor order, so onRequest is always seen once per
    // attempt no matter where consumers sit.
    _dio.interceptors.addAll([
      if (pinning != null)
        CertificatePinningInterceptor(
          allowedSHAFingerprints: pinning.allowedSHAFingerprints,
          timeout: pinning.timeout,
          // Leave the rest of the chain out of it: a pin failure is terminal,
          // so it must not reach retry (which would re-run the handshake for
          // the same verdict) or the 401 handler (which would read a security
          // event as an expired session).
          callFollowingErrorInterceptor: false,
        ),
      ...config.interceptors,
      _buildRetryInterceptor(config.retry),
      UnAuthInterceptor(onUnauthorized: config.onUnauthorized),
      if (kDebugMode) _buildLoggerInterceptor(),
    ]);

    // Mutually exclusive with pinning (see _resolvePinning), so this only
    // ever fires on an unpinned client.
    if (config.allowBadCertificate) {
      (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient =
          () => io.HttpClient()..badCertificateCallback = (_, __, ___) => true;
    }
  }

  /// Returns the pinning configuration for [config], or `null` when pinning
  /// is off.
  ///
  /// Throws [ArgumentError] when pinning is combined with
  /// [NetworkConfig.allowBadCertificate]. The check lives here rather than in
  /// `NetworkConfig`'s const constructor because a const constructor can only
  /// `assert`, and asserts are stripped from release builds — exactly where
  /// shipping an app that looks pinned but is not would do the damage.
  CertificatePinningConfig? _resolvePinning(NetworkConfig config) {
    final pinning = config.certificatePinning;
    if (pinning == null) return null;

    if (config.allowBadCertificate) {
      throw ArgumentError(
        'NetworkConfig sets both allowBadCertificate: true and '
        'certificatePinning. That combination is incoherent — '
        'allowBadCertificate disables certificate validation while '
        'certificatePinning tightens it — and accepting it would produce an '
        'app that looks pinned but is not. Drop allowBadCertificate from any '
        'build that pins.',
      );
    }

    return pinning;
  }

  /// Builds the retry interceptor for [globalPolicy].
  ///
  /// The interceptor is installed unconditionally, even when retry is off
  /// app-wide, because a single request can still opt in by attaching its own
  /// [RetryPolicy]. Every decision is deferred to [evaluateRetry], which is
  /// the only place that can see the per-request policy.
  ///
  /// [RetryInterceptor.retries] is therefore set to the [RetryPolicy]
  /// ceiling rather than the configured attempt count: the library
  /// short-circuits on that field *before* consulting the evaluator, so a
  /// lower value would silently cap a request that asked for more.
  RetryInterceptor _buildRetryInterceptor(RetryPolicy? globalPolicy) {
    return RetryInterceptor(
      dio: _dio,
      logPrint: kDebugMode ? log : null,
      retries: RetryPolicy.maxAttempts,
      retryDelays: globalPolicy?.delays ?? kDefaultRetryDelays,
      retryEvaluator: (error, attempt) =>
          evaluateRetry(error, attempt, globalPolicy),
    );
  }

  PrettyDioLogger _buildLoggerInterceptor() => PrettyDioLogger(
        requestHeader: true,
        requestBody: true,
        responseBody: true,
        responseHeader: false,
        error: true,
        compact: true,
        maxWidth: 80,
      );

  Dio get dio => _dio;

  void dispose() => _dio.close();
}
