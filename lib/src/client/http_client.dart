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

    _dio.interceptors.addAll([
      _buildRetryInterceptor(),
      if (kDebugMode) _buildLoggerInterceptor(),
      UnAuthInterceptor(onUnauthorized: config.onUnauthorized),
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
