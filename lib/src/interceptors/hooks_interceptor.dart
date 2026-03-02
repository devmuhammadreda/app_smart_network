import 'package:dio/dio.dart';

import '../config/network_config.dart';

// ============================================================================
// HOOKS INTERCEPTOR
// ============================================================================

/// Applies consumer-registered [RequestHook] and [ResponseHook] pipelines.
///
/// **Request hooks** are applied in registration order on every outgoing
/// request, except when the request is tagged with `extra['_skipHooks'] == true`
/// (used internally by [TokenRefreshInterceptor] to prevent hooks re-running
/// on the token-refresh retry).
///
/// **Response hooks** are applied in registration order on every successful
/// (2xx) response. Error responses bypass this interceptor entirely and go
/// directly to the error chain.
///
/// This interceptor is registered **first** in the Dio chain so that request
/// hooks run before any retry or auth logic, and response hooks run before the
/// response is returned to the caller.
class HooksInterceptor extends Interceptor {
  final NetworkConfig _config;

  HooksInterceptor(this._config);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Skip hooks on token-refresh retry requests.
    if (options.extra['_skipHooks'] == true) {
      handler.next(options);
      return;
    }

    var current = options;
    for (final hook in _config.requestHooks) {
      current = await Future.value(hook(current));
    }
    handler.next(current);
  }

  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    var current = response;
    for (final hook in _config.responseHooks) {
      current = await Future.value(hook(current));
    }
    handler.next(current);
  }
}
