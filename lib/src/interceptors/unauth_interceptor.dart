import 'package:dio/dio.dart';

import '../config/network_config.dart';

// ============================================================================
// UNAUTHORIZED INTERCEPTOR  (deprecated — internal use only)
// ============================================================================

/// @deprecated
///
/// This interceptor is no longer registered by [HttpClient].
/// 401 handling is now done by [TokenRefreshInterceptor], which calls
/// [NetworkConfig.onUnauthorized] when a refresh is not configured or fails.
///
/// This class is kept for source compatibility and will be removed in v2.0.0.
@Deprecated(
  'UnAuthInterceptor is no longer registered by HttpClient. '
  '401 handling is performed by TokenRefreshInterceptor. '
  'This class will be removed in v2.0.0.',
)
class UnAuthInterceptor extends Interceptor {
  final OnUnauthorizedCallback? onUnauthorized;

  UnAuthInterceptor({this.onUnauthorized});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(err);
  }
}
