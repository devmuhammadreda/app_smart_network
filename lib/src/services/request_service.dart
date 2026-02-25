import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import '../client/http_client.dart';
import '../error/error_handler.dart';
import '../mixins/network_service_mixin.dart';

/// Available HTTP methods.
enum HttpMethod { get, post, put, patch, delete }

// ============================================================================
// REQUEST SERVICE
// ============================================================================

class RequestService with NetworkServiceMixin {
  final HttpClient _client;

  @override
  final Connectivity connectivity;

  RequestService(this._client, {Connectivity? connectivity})
      : connectivity = connectivity ?? Connectivity();

  Future<Response<T>> execute<T>(
    HttpMethod method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    String? baseUrl,
  }) async {
    try {
      final conn = await ensureConnected();
      final opts = withMobileTimeouts(
        options,
        conn,
        mobileReceiveTimeout: const Duration(milliseconds: 30000),
      );
      final url = resolveUrl(path, baseUrl);

      switch (method) {
        case HttpMethod.get:
          return await _client.dio.get<T>(
            url,
            queryParameters: queryParameters,
            options: opts,
            cancelToken: cancelToken,
            onReceiveProgress: (r, t) => handleProgress(r, t, onReceiveProgress),
          );
        case HttpMethod.post:
          return await _client.dio.post<T>(
            url,
            data: data,
            queryParameters: queryParameters,
            options: opts,
            cancelToken: cancelToken,
            onSendProgress: (s, t) => handleProgress(s, t, onSendProgress),
            onReceiveProgress: (r, t) => handleProgress(r, t, onReceiveProgress),
          );
        case HttpMethod.put:
          return await _client.dio.put<T>(
            url,
            data: data,
            queryParameters: queryParameters,
            options: opts,
            cancelToken: cancelToken,
            onSendProgress: (s, t) => handleProgress(s, t, onSendProgress),
            onReceiveProgress: (r, t) => handleProgress(r, t, onReceiveProgress),
          );
        case HttpMethod.patch:
          return await _client.dio.patch<T>(
            url,
            data: data,
            queryParameters: queryParameters,
            options: opts,
            cancelToken: cancelToken,
            onSendProgress: (s, t) => handleProgress(s, t, onSendProgress),
            onReceiveProgress: (r, t) => handleProgress(r, t, onReceiveProgress),
          );
        case HttpMethod.delete:
          return await _client.dio.delete<T>(
            url,
            data: data,
            queryParameters: queryParameters,
            options: opts,
            cancelToken: cancelToken,
          );
      }
    } catch (e) {
      throw ErrorHandler.handleError(e);
    }
  }
}
