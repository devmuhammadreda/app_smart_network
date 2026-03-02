import 'dart:convert';
import 'dart:developer';
import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../config/network_config.dart';
import '../interceptors/hooks_interceptor.dart';
import '../interceptors/token_refresh_interceptor.dart';

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
  late final NetworkConfig _config;

  HttpClient(NetworkConfig config) {
    _config = config;
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

    // Interceptor order (onRequest FIFO, onError LIFO):
    //   1. HooksInterceptor       – request hooks first; response hooks first on 2xx
    //   2. RetryInterceptor       – retries non-401 errors
    //   3. PrettyDioLogger        – debug logging (debug builds only)
    //   4. TokenRefreshInterceptor – onError called FIRST (LIFO): intercepts 401
    _dio.interceptors.addAll([
      HooksInterceptor(config),
      _buildRetryInterceptor(),
      if (kDebugMode) _buildLoggerInterceptor(),
      TokenRefreshInterceptor(_dio, config),
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
        // Never retry 401 — TokenRefreshInterceptor owns that status code.
        if (error.response?.statusCode == 401) return false;
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

  NetworkConfig get config => _config;

  void dispose() => _dio.close();
}
