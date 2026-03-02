import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import '../client/http_client.dart';
import '../error/error_handler.dart';
import '../mixins/network_service_mixin.dart';

/// Available HTTP methods.
enum HttpMethod { get, post, put, patch, delete }

// ============================================================================
// DEDUPLICATION SUPPORT
// ============================================================================

/// Internal state for a single in-flight deduplicated request.
class _DeduplicationEntry {
  final Completer<Response<dynamic>> completer;
  int waiterCount = 0;
  CancelToken cancelToken;

  _DeduplicationEntry({
    required this.completer,
    required this.cancelToken,
  });
}

// ============================================================================
// REQUEST SERVICE
// ============================================================================

class RequestService with NetworkServiceMixin {
  final HttpClient _client;

  @override
  final Connectivity connectivity;

  /// In-flight deduplicated requests keyed by a canonical request key.
  final Map<String, _DeduplicationEntry> _pendingRequests = {};

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
    bool deduplicate = false,
  }) async {
    if (deduplicate) {
      return _executeWithDeduplication<T>(
        method,
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
        baseUrl: baseUrl,
      );
    }

    return _doRequest<T>(
      method,
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      baseUrl: baseUrl,
    );
  }

  Future<Response<T>> _executeWithDeduplication<T>(
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
    final conn = await ensureConnected();
    final opts = withMobileTimeouts(
      options,
      conn,
      mobileReceiveTimeout: const Duration(milliseconds: 30000),
    );
    final resolvedUrl = resolveUrl(path, baseUrl);
    final key = _buildDeduplicationKey(
      method.name.toUpperCase(),
      resolvedUrl,
      queryParameters,
      opts.headers,
    );

    final existing = _pendingRequests[key];
    if (existing != null) {
      // Another identical request is in-flight — piggyback on it.
      existing.waiterCount++;
      try {
        final response = await existing.completer.future;
        return response as Response<T>;
      } finally {
        existing.waiterCount--;
      }
    }

    // First caller for this key — issue the actual network request.
    final internalCancel = CancelToken();
    final entry = _DeduplicationEntry(
      completer: Completer<Response<dynamic>>(),
      cancelToken: internalCancel,
    );
    _pendingRequests[key] = entry;

    // Monitor the caller's external cancel token.
    if (cancelToken != null) {
      cancelToken.whenCancel.then((_) {
        if (entry.waiterCount > 0) {
        // Waiters still present — promote a new request on their behalf.
          _promoteNewRequest<T>(key, entry, method, resolvedUrl,
              data: data,
              queryParameters: queryParameters,
              options: opts,
              onSendProgress: onSendProgress,
              onReceiveProgress: onReceiveProgress);
        } else {
          internalCancel.cancel('Original caller cancelled');
        }
      });
    }

    try {
      final response = await _doRequest<T>(
        method,
        path,
        data: data,
        queryParameters: queryParameters,
        options: opts,
        cancelToken: internalCancel,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
        baseUrl: baseUrl,
      );
      entry.completer.complete(response);
      return response;
    } catch (e) {
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(e);
      }
      rethrow;
    } finally {
      _pendingRequests.remove(key);
    }
  }

  /// Re-issues the request when the original caller cancelled but waiters remain.
  void _promoteNewRequest<T>(
    String key,
    _DeduplicationEntry entry,
    HttpMethod method,
    String resolvedUrl, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    final newCancel = CancelToken();
    entry.cancelToken = newCancel;

    _doRequest<T>(
      method,
      resolvedUrl,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: newCancel,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    ).then((response) {
      if (!entry.completer.isCompleted) {
        entry.completer.complete(response);
      }
    }).catchError((e) {
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(e);
      }
    }).whenComplete(() => _pendingRequests.remove(key));
  }

  Future<Response<T>> _doRequest<T>(
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
      final opts = options ??
          withMobileTimeouts(
            null,
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
      throw await ErrorHandler.handleError(
        e,
        parser: _client.config.errorBodyParser,
      );
    }
  }

  /// Builds a stable, order-independent deduplication key.
  ///
  /// Format: `METHOD|url|sortedQueryParams|sortedHeaders`
  static String _buildDeduplicationKey(
    String method,
    String url,
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
  ) {
    final q = query == null
        ? ''
        : (query.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key)))
            .map((e) => '${e.key}=${e.value}')
            .join('&');

    final h = headers == null
        ? ''
        : (headers.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key)))
            .map((e) => '${e.key}:${e.value}')
            .join(',');

    return '$method|$url|$q|$h';
  }
}
