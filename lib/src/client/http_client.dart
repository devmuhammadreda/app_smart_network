import 'dart:convert';
import 'dart:developer';
import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../config/network_config.dart';
import '../interceptors/unauth_interceptor.dart';

// ── Background JSON decoding ───────────────────────────────────────────────

dynamic _parseAndDecode(String response) => jsonDecode(response);
Future<dynamic> _parseJsonInBg(String text) => compute(_parseAndDecode, text);

// ── Idempotent HTTP methods (safe to retry automatically) ──────────────────

const _idempotentMethods = {'GET', 'PUT', 'DELETE', 'HEAD', 'OPTIONS'};

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
      ...config.interceptors,
      _buildRetryInterceptor(),
      UnAuthInterceptor(onUnauthorized: config.onUnauthorized),
      if (kDebugMode) _buildLoggerInterceptor(),
    ]);

    if (config.allowBadCertificate) {
      (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () =>
          io.HttpClient()..badCertificateCallback = (_, __, ___) => true;
    }
  }

  RetryInterceptor _buildRetryInterceptor() {
    final evaluator = DefaultRetryEvaluator(defaultRetryableStatuses);
    return RetryInterceptor(
      dio: _dio,
      logPrint: kDebugMode ? log : null,
      retries: 3,
      retryDelays: const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 3),
      ],
      retryEvaluator: (error, attempt) {
        final method = error.requestOptions.method.toUpperCase();
        if (!_idempotentMethods.contains(method)) return false;
        return evaluator.evaluate(error, attempt);
      },
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
