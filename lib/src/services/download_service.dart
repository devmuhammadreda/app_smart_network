import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import '../client/http_client.dart';
import '../config/retry_policy.dart';
import '../error/error_handler.dart';
import '../mixins/network_service_mixin.dart';

// ============================================================================
// DOWNLOAD SERVICE
// ============================================================================

class DownloadRequestService with NetworkServiceMixin {
  final HttpClient _client;

  @override
  final Connectivity connectivity;

  DownloadRequestService(this._client, {Connectivity? connectivity})
      : connectivity = connectivity ?? Connectivity();

  Future<Response> execute(
    String urlPath,
    String savePath, {
    ProgressCallback? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    String lengthHeader = Headers.contentLengthHeader,
    Options? options,
    String? baseUrl,
    RetryPolicy? retry,
  }) async {
    final conn = await ensureConnected();
    final opts = attachRetryPolicy(withMobileTimeouts(options, conn), retry);
    final url = resolveUrl(urlPath, baseUrl);

    try {
      return await _client.dio.download(
        url,
        savePath,
        onReceiveProgress: (r, t) => handleProgress(r, t, onReceiveProgress),
        queryParameters: queryParameters,
        cancelToken: cancelToken,
        deleteOnError: deleteOnError,
        lengthHeader: lengthHeader,
        options: opts,
      );
    } catch (e) {
      throw ErrorHandler.handleError(e);
    }
  }
}
