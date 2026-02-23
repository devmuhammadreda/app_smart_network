import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../error/exceptions.dart';
import '../i18n/network_locale.dart';

// ============================================================================
// NETWORK SERVICE MIXIN
// ============================================================================

mixin NetworkServiceMixin {
  Connectivity get connectivity;

  /// Verifies connectivity, throwing [ApiException] when offline.
  ///
  /// A single 600 ms retry is performed to handle transient states that
  /// connectivity_plus may report right after app launch or enabling Wi-Fi.
  Future<List<ConnectivityResult>> ensureConnected() async {
    var result = await connectivity.checkConnectivity();
    if (result.contains(ConnectivityResult.none)) {
      await Future.delayed(const Duration(milliseconds: 600));
      result = await connectivity.checkConnectivity();
    }
    if (result.contains(ConnectivityResult.none)) {
      throw ApiException(
        NetworkLocale.getErrorMessage('NoInternetConnection'),
        0,
        errorType: 'NoInternetConnection',
      );
    }
    return result;
  }

  /// Forwards download/upload progress to [callback] and logs it.
  void handleProgress(int current, int total, ProgressCallback? callback) {
    if (callback != null && total != -1) {
      callback(current, total);
      final pct = (current / total * 100).toStringAsFixed(0);
      debugPrint('[$runtimeType] progress: $pct%');
    }
  }

  /// Returns request [Options] with an extended receive-timeout when the
  /// device is on a mobile network. User-provided values take precedence.
  ///
  /// Mutates [userOptions] in-place (or creates a new [Options] if null)
  /// so that all caller-supplied fields are preserved.
  Options withMobileTimeouts(
    Options? userOptions,
    List<ConnectivityResult> connectivityResult, {
    Duration mobileReceiveTimeout = const Duration(milliseconds: 40000),
  }) {
    final opts = userOptions ?? Options();
    if (connectivityResult.contains(ConnectivityResult.mobile)) {
      // Only apply when the caller hasn't already set a custom timeout.
      opts.receiveTimeout ??= mobileReceiveTimeout;
    }
    return opts;
  }

  /// Resolves the full URL. When [baseUrl] is non-null it is prepended to
  /// [path] and used as-is, bypassing Dio's own baseUrl.
  String resolveUrl(String path, String? baseUrl) =>
      baseUrl != null ? '$baseUrl$path' : path;
}
