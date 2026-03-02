import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/network_config.dart';

// ============================================================================
// TOKEN REFRESH INTERCEPTOR
// ============================================================================

/// Intercepts 401 responses and transparently refreshes the access token.
///
/// When multiple in-flight requests all receive 401 simultaneously, the token
/// refresh callback is called **exactly once**. All other waiters receive the
/// same new token when the refresh completes.
///
/// The interceptor is registered **last** in the Dio interceptor chain so that
/// its `onError` handler is called **first** (Dio's LIFO error ordering),
/// preventing `RetryInterceptor` from seeing 401 responses.
class TokenRefreshInterceptor extends Interceptor {
  final NetworkConfig _config;
  final Dio _dio;

  bool _isRefreshing = false;
  Completer<String?>? _refreshCompleter;

  TokenRefreshInterceptor(this._dio, this._config);

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }

    final tokenRefresher = _config.tokenRefresher;
    if (tokenRefresher == null) {
      // No refresh configured — fall through to onUnauthorized.
      _config.onUnauthorized?.call();
      handler.next(err);
      return;
    }

    // Check if this 401 came from the refresh endpoint itself.
    if (_isRefreshEndpoint(err.requestOptions.uri.toString())) {
      debugPrint('[AppSmartNetwork] Refresh endpoint returned 401 – aborting.');
      _config.onUnauthorized?.call();
      handler.next(err);
      return;
    }

    if (_isRefreshing) {
      // Another request already started the refresh — wait for it.
      final newToken = await _refreshCompleter!.future;
      if (newToken != null) {
        handler.resolve(await _retry(err.requestOptions, newToken));
      } else {
        handler.next(err);
      }
      return;
    }

    // First 401 — start the refresh.
    _isRefreshing = true;
    _refreshCompleter = Completer<String?>();
    try {
      final newToken = await tokenRefresher();
      _refreshCompleter!.complete(newToken);

      if (newToken != null) {
        // Update the Dio default headers for subsequent requests.
        _dio.options.headers['Authorization'] = 'Bearer $newToken';
        handler.resolve(await _retry(err.requestOptions, newToken));
      } else {
        _config.onUnauthorized?.call();
        handler.next(err);
      }
    } catch (_) {
      _refreshCompleter!.complete(null);
      _config.onUnauthorized?.call();
      handler.next(err);
    } finally {
      _isRefreshing = false;
      _refreshCompleter = null;
    }
  }

  bool _isRefreshEndpoint(String url) {
    final predicate = _config.refreshEndpointPredicate;
    return predicate != null && predicate(url);
  }

  Future<Response<dynamic>> _retry(
    RequestOptions requestOptions,
    String newToken,
  ) async {
    final retryOptions = requestOptions.copyWith(
      headers: {
        ...requestOptions.headers,
        'Authorization': 'Bearer $newToken',
      },
      extra: {
        ...requestOptions.extra,
        '_skipHooks': true,
      },
    );
    return _dio.fetch(retryOptions);
  }
}
