import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/network_config.dart';

// ============================================================================
// UNAUTHORIZED INTERCEPTOR
// ============================================================================

class UnAuthInterceptor extends Interceptor {
  final OnUnauthorizedCallback? onUnauthorized;

  UnAuthInterceptor({this.onUnauthorized});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      debugPrint('[AppSmartNetwork] 401 Unauthorized – session expired.');
      onUnauthorized?.call();
    }
    handler.next(err);
  }
}
