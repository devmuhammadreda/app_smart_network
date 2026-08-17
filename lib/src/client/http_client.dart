import 'dart:convert';
import 'dart:developer';
import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../config/network_config.dart';
import '../config/retry_policy.dart';
import '../i18n/network_locale.dart';
import '../interceptors/pinning_interceptor.dart';
import '../interceptors/unauth_interceptor.dart';
import '../security/certificate_pinner.dart';

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
    final pinner = _buildPinner(config);

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
      if (pinner != null)
        PinningInterceptor(
          pinner,
          () => NetworkLocale.getErrorMessage('CertificatePinningFailed'),
        ),
      ...config.interceptors,
      _buildRetryInterceptor(config.retry),
      UnAuthInterceptor(onUnauthorized: config.onUnauthorized),
      if (kDebugMode) _buildLoggerInterceptor(),
    ]);

    // The two settings are mutually exclusive (see _buildPinner), so this is
    // one adapter configured one way or the other, never both.
    if (config.allowBadCertificate) {
      (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient =
          () => io.HttpClient()..badCertificateCallback = (_, __, ___) => true;
    } else if (pinner != null) {
      // validateCertificate, not badCertificateCallback: the latter fires only
      // once default chain validation has already failed, so it can never add
      // pinning on top of an otherwise-valid certificate. validateCertificate
      // evaluates the leaf on every connection, which is what pinning needs.
      (_dio.httpClientAdapter as IOHttpClientAdapter).validateCertificate =
          pinner.validate;
    }
  }

  /// Returns the pinner for [config], or `null` when pinning is off.
  ///
  /// Throws [ArgumentError] when pinning is combined with
  /// [NetworkConfig.allowBadCertificate]. The check lives here rather than in
  /// `NetworkConfig`'s const constructor because a const constructor can only
  /// `assert`, and asserts are stripped from release builds — exactly where
  /// shipping an app that looks pinned but is not would do the damage.
  CertificatePinner? _buildPinner(NetworkConfig config) {
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

    return CertificatePinner(pinning);
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
